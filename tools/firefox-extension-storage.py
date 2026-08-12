#!/usr/bin/env python3
"""Dump a Firefox WebExtension's browser.storage.local as JSON.

Why this exists: extension settings that have no export button (or whose export
button emits a lossy subset) are otherwise trapped in the browser profile. This
recovered a FoxyProxy config whose proxy patterns had been lost from the UI but
were still on disk.

Usage:
    tools/firefox-extension-storage.py <extension-id> [--profile NAME] [--list]

    # FoxyProxy in the default profile
    tools/firefox-extension-storage.py foxyproxy@eric.h.jung

    # See which extensions have stored data
    tools/firefox-extension-storage.py --list

Note Firefox's profile root is $HOME/.mozilla/firefox on most builds but
$HOME/.config/mozilla/firefox on newer XDG-respecting ones (Arch/CachyOS as of
2026). Both are probed.

--- Format notes -----------------------------------------------------------

Locating the data takes two hops. Extensions are addressed on disk by a
per-profile random UUID, not by their ID; the mapping lives in prefs.js under
`extensions.webextensions.uuids`. The storage itself is at:

    <profile>/storage/default/moz-extension+++<uuid>^userContextId=4294967295/idb/*.sqlite

The `^userContextId=4294967295` suffix is the one that matters -- the bare
directory usually holds only localStorage, not storage.local.

Each row of the `object_data` table then has two layers:

  1. Snappy, raw/unframed (no stream header). Implemented here rather than
     depending on python-snappy, which is not packaged on every distro.

  2. Structured Clone: little-endian 64-bit words, each (payload:u32, tag:u32)
     in memory order, so `tag = word >> 32`. Tags from
     js/src/vm/StructuredClone.cpp:

         0xFFFF0000 NULL       0xFFFF0004 STRING
         0xFFFF0001 UNDEFINED  0xFFFF0007 ARRAY  (payload = length)
         0xFFFF0002 BOOLEAN    0xFFFF0008 OBJECT
         0xFFFF0003 INT32      0xFFFF0013 END_OF_KEYS

     Objects and arrays both emit (key, value) pairs terminated by END_OF_KEYS;
     array keys are INT32 indices. String data follows its tag word inline,
     padded to the next 8-byte boundary; payload bit 31 marks latin1 (vs
     UTF-16LE) and bits 0-30 are the character count. A word whose tag is
     <= 0xFFF00000 is not a tag at all -- it is a raw IEEE-754 double.

Row keys use Firefox's own key encoding: a 0x30 type byte for "string",
then each character byte stored +1.
"""
import argparse
import glob
import json
import os
import re
import shutil
import sqlite3
import struct
import sys
import tempfile

PROFILE_ROOTS = [
    os.path.expanduser("~/.mozilla/firefox"),
    os.path.expanduser("~/.config/mozilla/firefox"),
    os.path.expanduser("~/snap/firefox/common/.mozilla/firefox"),
    os.path.expanduser("~/.var/app/org.mozilla.firefox/.mozilla/firefox"),
]

# --- layer 1: raw Snappy -----------------------------------------------------


def snappy_decompress(buf):
    pos = 0
    length = shift = 0
    while True:  # uncompressed length, varint
        b = buf[pos]
        pos += 1
        length |= (b & 0x7F) << shift
        if not b & 0x80:
            break
        shift += 7

    out = bytearray()
    while pos < len(buf):
        tag = buf[pos]
        kind = tag & 0x03
        if kind == 0:  # literal
            n = tag >> 2
            pos += 1
            if n >= 60:
                extra = n - 59
                n = int.from_bytes(buf[pos:pos + extra], "little")
                pos += extra
            n += 1
            out += buf[pos:pos + n]
            pos += n
            continue
        if kind == 1:  # copy, 1-byte offset
            n = ((tag >> 2) & 0x07) + 4
            off = ((tag >> 5) << 8) | buf[pos + 1]
            pos += 2
        elif kind == 2:  # copy, 2-byte offset
            n = (tag >> 2) + 1
            off = int.from_bytes(buf[pos + 1:pos + 3], "little")
            pos += 3
        else:  # copy, 4-byte offset
            n = (tag >> 2) + 1
            off = int.from_bytes(buf[pos + 1:pos + 5], "little")
            pos += 5
        start = len(out) - off
        for i in range(n):  # copies may overlap; byte at a time
            out.append(out[start + i])

    if len(out) != length:
        raise ValueError(f"snappy length mismatch: {len(out)} != {length}")
    return bytes(out)


# --- layer 2: structured clone -----------------------------------------------

NULL, UNDEF, BOOL, INT32, STRING = 0xFFFF0000, 0xFFFF0001, 0xFFFF0002, 0xFFFF0003, 0xFFFF0004
ARRAY, OBJECT, END_OF_KEYS, HEADER = 0xFFFF0007, 0xFFFF0008, 0xFFFF0013, 0xFFF10000
DOUBLE_TAG_MAX = 0xFFF00000


class Reader:
    def __init__(self, buf):
        self.buf, self.pos = buf, 0

    def word(self):
        w = struct.unpack_from("<Q", self.buf, self.pos)[0]
        self.pos += 8
        return w

    def peek_tag(self):
        return struct.unpack_from("<Q", self.buf, self.pos)[0] >> 32

    def value(self):
        w = self.word()
        tag, payload = w >> 32, w & 0xFFFFFFFF

        if tag <= DOUBLE_TAG_MAX:
            return struct.unpack("<d", struct.pack("<Q", w))[0]
        if tag in (NULL, UNDEF):
            return None
        if tag == BOOL:
            return bool(payload)
        if tag == INT32:
            return struct.unpack("<i", struct.pack("<I", payload))[0]
        if tag == STRING:
            latin1 = bool(payload & 0x80000000)
            count = payload & 0x7FFFFFFF
            nbytes = count if latin1 else count * 2
            raw = self.buf[self.pos:self.pos + nbytes]
            self.pos += (nbytes + 7) & ~7
            return raw.decode("latin-1" if latin1 else "utf-16-le")
        if tag == ARRAY:
            out = [None] * payload
            while self.peek_tag() != END_OF_KEYS:
                idx, val = self.value(), self.value()
                if isinstance(idx, int) and 0 <= idx < len(out):
                    out[idx] = val
            self.word()
            return out
        if tag == OBJECT:
            out = {}
            while self.peek_tag() != END_OF_KEYS:
                # Must be two statements: in `out[self.value()] = self.value()`
                # Python evaluates the right-hand side FIRST, which would read
                # the value before the key and desynchronise the whole stream.
                key = self.value()
                out[key] = self.value()
            self.word()
            return out
        raise ValueError(f"unhandled structured-clone tag 0x{tag:08X}")


def read_clone(buf):
    r = Reader(buf)
    if r.peek_tag() == HEADER:
        r.word()
    return r.value()


# --- locating the data -------------------------------------------------------


def decode_key(blob):
    if blob and blob[0] == 0x30:
        return "".join(chr(b - 1) for b in blob[1:])
    return repr(blob)


def profiles():
    for root in PROFILE_ROOTS:
        if not os.path.isdir(root):
            continue
        for entry in sorted(os.listdir(root)):
            path = os.path.join(root, entry)
            if os.path.isfile(os.path.join(path, "prefs.js")):
                yield entry, path


def uuid_map(profile_path):
    """extension id -> per-profile UUID, from prefs.js."""
    try:
        with open(os.path.join(profile_path, "prefs.js"), encoding="utf-8", errors="replace") as fh:
            prefs = fh.read()
    except OSError:
        return {}
    m = re.search(r'"extensions\.webextensions\.uuids",\s*"(.*?)"\);', prefs, re.S)
    if not m:
        return {}
    # The value is a JSON object that has been escaped for embedding in prefs.js.
    return json.loads(m.group(1).replace('\\"', '"'))


def storage_db(profile_path, uuid):
    pattern = os.path.join(
        profile_path, "storage", "default",
        f"moz-extension+++{uuid}^userContextId=4294967295", "idb", "*.sqlite",
    )
    hits = sorted(glob.glob(pattern))
    if not hits:  # some profiles keep it on the unsuffixed origin
        hits = sorted(glob.glob(os.path.join(
            profile_path, "storage", "default",
            f"moz-extension+++{uuid}", "idb", "*.sqlite")))
    return hits[0] if hits else None


def dump_db(path):
    # Copy the database and its sidecars aside before opening. Firefox may be
    # running, and recent writes can still be sitting in the -wal; opening the
    # original with immutable=1 would silently skip the WAL and return stale
    # values, while opening it read-write would disturb a live profile.
    with tempfile.TemporaryDirectory() as tmp:
        base = os.path.join(tmp, os.path.basename(path))
        for suffix in ("", "-wal", "-shm"):
            src = path + suffix
            if os.path.exists(src):
                shutil.copy2(src, base + suffix)
        con = sqlite3.connect(base)
        try:
            out = {}
            for key, data in con.execute("select key, data from object_data"):
                out[decode_key(key)] = read_clone(snappy_decompress(data))
            return out
        finally:
            con.close()


def main():
    ap = argparse.ArgumentParser(
        description="Dump a Firefox WebExtension's browser.storage.local as JSON.")
    ap.add_argument("extension_id", nargs="?", help="e.g. foxyproxy@eric.h.jung")
    ap.add_argument("--profile", help="profile directory name (default: every profile)")
    ap.add_argument("--list", action="store_true", help="list extensions with stored data")
    args = ap.parse_args()

    if not args.extension_id and not args.list:
        ap.error("give an extension id, or --list")

    found = False
    for name, path in profiles():
        if args.profile and args.profile != name:
            continue
        mapping = uuid_map(path)

        if args.list:
            rows = [(ext, storage_db(path, u)) for ext, u in sorted(mapping.items())]
            rows = [(ext, db) for ext, db in rows if db]
            if rows:
                print(f"# profile: {name}", file=sys.stderr)
                for ext, _ in rows:
                    print(f"  {ext}", file=sys.stderr)
            continue

        uuid = mapping.get(args.extension_id)
        if not uuid:
            continue
        db = storage_db(path, uuid)
        if not db:
            print(f"# {name}: extension present but no stored data", file=sys.stderr)
            continue
        print(f"# profile: {name}", file=sys.stderr)
        print(json.dumps(dump_db(db), indent=2))
        found = True

    if args.extension_id and not found:
        print(f"no stored data for {args.extension_id} in any profile", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
