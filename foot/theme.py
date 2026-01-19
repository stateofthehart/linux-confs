#!/usr/bin/env python3
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import List, Tuple, Dict, Optional

THEMES_DIR = Path.home() / ".config" / "foot" / "themes"
FOOT_INI   = Path.home() / ".config" / "foot" / "foot.ini"
BACKUP_DIR = Path.home() / ".config" / "foot" / "backups"

SECTION_RE = re.compile(r"^\s*\[(.+?)\]\s*$")

def eprint(*args):
    print(*args, file=sys.stderr)

def ansi_palette_preview(title: str = "Preview"):
    # 16-color palette blocks + a couple sample lines.
    print("\n" + "=" * 80)
    print(f"{title}")
    print("=" * 80)

    # 0-7 normal
    print("Normal  (0–7): ", end="")
    for i in range(8):
        print(f"\x1b[48;5;{i}m  \x1b[0m", end=" ")
    print()

    # 8-15 bright
    print("Bright  (8–15): ", end="")
    for i in range(8, 16):
        print(f"\x1b[48;5;{i}m  \x1b[0m", end=" ")
    print()

    # 256-color gradient hint
    print("256-color hint: ", end="")
    for i in [16, 17, 18, 19, 20, 21, 27, 33, 39, 45, 51, 87, 123, 159, 195, 231]:
        print(f"\x1b[48;5;{i}m  \x1b[0m", end=" ")
    print("\n")

    # Sample “hacker-y” text in various styles
    samples = [
        ("$ ", "\x1b[1;32m", "echo", "\x1b[0m", " ", "\x1b[36m", "THEME_TEST", "\x1b[0m"),
        ("# ", "\x1b[33m", "git status", "\x1b[0m", "  ", "\x1b[31m", "M", "\x1b[0m", "  foot.ini"),
        ("→ ", "\x1b[35m", "ssh", "\x1b[0m", " ", "\x1b[34m", "user@host", "\x1b[0m", "  ", "\x1b[90m", "(agent)", "\x1b[0m"),
        ("! ", "\x1b[31;1m", "warning:", "\x1b[0m", " disk at 92%"),
        ("✓ ", "\x1b[32;1m", "ok:", "\x1b[0m", " all services healthy"),
    ]
    for parts in samples:
        print("".join(parts))
    print()

def list_theme_files(themes_dir: Path) -> Dict[str, List[Path]]:
    """
    Returns mapping: group_name -> list of theme files.
    Group name is the first directory under themes_dir (or '.' for root files).
    """
    groups: Dict[str, List[Path]] = {}
    if not themes_dir.exists():
        return groups

    for p in themes_dir.rglob("*"):
        if p.is_dir():
            continue
        if p.name.startswith("."):
            continue
        # Heuristic: treat common theme file extensions (and extensionless) as candidates
        if p.suffix.lower() not in (".ini", ".conf", ".theme", ".toml", ""):
            continue
        rel = p.relative_to(themes_dir)
        group = rel.parts[0] if len(rel.parts) > 1 else "."
        groups.setdefault(group, []).append(p)

    # Sort paths within each group
    for g in groups:
        groups[g] = sorted(groups[g], key=lambda x: str(x).lower())
    return dict(sorted(groups.items(), key=lambda kv: kv[0].lower()))

def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")

def theme_content_normalized(theme_path: Path) -> str:
    """
    Normalize theme content into valid foot.ini snippet containing [colors] (and optionally [colors2]).
    If file already contains [colors], return as-is.
    If it looks like key=value lines, wrap in [colors].
    """
    raw = read_text(theme_path).strip()

    # If it already declares a [colors] section, assume it's a valid snippet
    if re.search(r"(?m)^\s*\[colors\]\s*$", raw):
        return raw + "\n"

    # If it declares other sections but not colors, don't try to merge as colors
    if re.search(r"(?m)^\s*\[.+?\]\s*$", raw):
        # Still return it; caller may choose to append or warn
        return raw + "\n"

    # Otherwise treat as key=value list and wrap
    # Filter out empty/comment-only lines to keep it clean
    lines = []
    for line in raw.splitlines():
        s = line.strip()
        if not s or s.startswith("#") or s.startswith(";"):
            continue
        lines.append(line)
    wrapped = "[colors]\n" + "\n".join(lines) + "\n"
    return wrapped

def strip_sections(lines: List[str], section_names: Tuple[str, ...]) -> List[str]:
    """
    Remove specified sections entirely from a foot.ini file (by section header).
    Keeps everything else.
    """
    out: List[str] = []
    i = 0
    while i < len(lines):
        m = SECTION_RE.match(lines[i])
        if m:
            name = m.group(1).strip().lower()
            if name in [s.lower() for s in section_names]:
                # Skip until next section header or EOF
                i += 1
                while i < len(lines) and not SECTION_RE.match(lines[i]):
                    i += 1
                continue
        out.append(lines[i])
        i += 1
    return out

def upsert_colors_into_foot_ini(theme_snippet: str):
    """
    Replace [colors] and [colors2] in ~/.config/foot/foot.ini with theme snippet's [colors]/[colors2] sections.
    If foot.ini doesn't exist, create a minimal one with theme snippet.
    """
    FOOT_INI.parent.mkdir(parents=True, exist_ok=True)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)

    # Backup existing
    if FOOT_INI.exists():
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_path = BACKUP_DIR / f"foot.ini.{ts}.bak"
        shutil.copy2(FOOT_INI, backup_path)
        print(f"Backed up existing foot.ini -> {backup_path}")

    # Parse theme snippet; extract [colors] and [colors2] blocks if present
    snippet_lines = theme_snippet.splitlines(keepends=True)
    # Identify whether snippet contains colors sections
    has_colors = any(re.match(r"^\s*\[colors\]\s*$", l) for l in snippet_lines)
    has_colors2 = any(re.match(r"^\s*\[colors2\]\s*$", l) for l in snippet_lines)

    # If snippet has no [colors], treat whole snippet as [colors] (already normalized should avoid this)
    if not has_colors:
        theme_snippet = theme_content_normalized(Path("/dev/null"))  # won't happen
        snippet_lines = theme_snippet.splitlines(keepends=True)

    # Load current foot.ini lines (or create)
    if FOOT_INI.exists():
        base_lines = FOOT_INI.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
        # Remove existing colors sections
        base_lines = strip_sections(base_lines, ("colors", "colors2"))
        # Ensure file ends with newline
        if base_lines and not base_lines[-1].endswith("\n"):
            base_lines[-1] += "\n"
    else:
        base_lines = [
            "# Generated/managed by theme switcher\n",
            "[main]\n",
            "font=monospace:size=12\n",
            "\n",
        ]

    # Append theme snippet at end (simple + robust)
    if base_lines and base_lines[-1].strip() != "":
        base_lines.append("\n")
    base_lines.append(theme_snippet.rstrip() + "\n")

    FOOT_INI.write_text("".join(base_lines), encoding="utf-8")
    print(f"Updated {FOOT_INI} with selected theme colors.")

def schedule_restart_foot():
    """
    Restart foot after a short delay so this script can finish even if run inside foot.
    Note: this kills all foot windows.
    """
    # Use a detached shell so the killing happens after we exit.
    # We try pkill by exact name. Then relaunch a new foot.
    cmd = "sh -lc 'sleep 0.25; pkill -x foot 2>/dev/null; sleep 0.15; nohup foot >/dev/null 2>&1 &'"
    try:
        subprocess.Popen(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        print("Restarting foot (kills existing foot windows) ...")
    except Exception as ex:
        eprint(f"Failed to schedule foot restart: {ex}")

def main():
    if not THEMES_DIR.exists():
        eprint(f"No themes directory found: {THEMES_DIR}")
        eprint("Create it and add theme files, e.g. ~/.config/foot/themes/<group>/<theme>.ini")
        sys.exit(1)

    groups = list_theme_files(THEMES_DIR)
    if not groups:
        eprint(f"No theme files found under: {THEMES_DIR}")
        sys.exit(1)

    # Flatten into numbered list with headers
    entries: List[Tuple[str, Path]] = []
    print("\nFOOT THEMES\n")
    idx = 1
    for group, files in groups.items():
        header = group if group != "." else "(root)"
        print(f"== {header} ==")
        for f in files:
            rel = f.relative_to(THEMES_DIR)
            print(f"  {idx:3d}) {rel}")
            entries.append((header, f))
            idx += 1
        print()

    print("Type a number to apply that theme.")
    print("Type 'p <n>' to preview only (no changes).")
    print("Type 'q' to quit.\n")

    while True:
        try:
            s = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return

        if s.lower() in ("q", "quit", "exit"):
            return

        preview_only = False
        if s.lower().startswith("p "):
            preview_only = True
            s = s[2:].strip()

        if not s.isdigit():
            print("Enter a number (or 'p <n>' or 'q').")
            continue

        n = int(s)
        if n < 1 or n > len(entries):
            print(f"Out of range: 1..{len(entries)}")
            continue

        group, path = entries[n - 1]
        rel = path.relative_to(THEMES_DIR)
        content = theme_content_normalized(path)

        ansi_palette_preview(f"Theme {n}: {rel}")

        # Show a tiny excerpt to confirm you're picking the right file
        excerpt = "\n".join(content.splitlines()[:40])
        print("---- theme snippet (first ~40 lines) ----")
        print(excerpt)
        if len(content.splitlines()) > 40:
            print("... (truncated)")
        print("----------------------------------------\n")

        if preview_only:
            continue

        ans = input(f"Apply theme '{rel}' to {FOOT_INI}? [y/N] ").strip().lower()
        if ans != "y":
            continue

        upsert_colors_into_foot_ini(content)
        schedule_restart_foot()
        print("Done.")
        return

if __name__ == "__main__":
    main()

