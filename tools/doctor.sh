#!/usr/bin/env bash
# doctor.sh — verify that what the configs REFERENCE actually EXISTS.
#
# Why this exists: install.sh validated the sway config's *syntax* but never
# checked that the things the configs point at are installed or working. On an
# established host that gap is invisible, because every dependency happens to
# already be there. Provisioning a genuinely blank machine (specter, Fedora
# aarch64, 2026-08) surfaced several latent bugs at once:
#
#   - `blueman` was in no package array, so waybar's bluetooth on-click was a
#     silent no-op; it had been hand-installed on wraith long ago
#   - volume.sh echoed a bare space instead of four Nerd Font glyphs, on BOTH
#     machines — a dropped glyph is invisible in a diff
#   - fallback-sink held `auto_null`, pointing volume.sh at a nonexistent sink
#   - install.sh aborted early via `set -e` on kanshi-only hosts
#   - three shell rc files sourced paths that only existed on wraith
#
# Run after install.sh, or whenever a bar module misbehaves. Exits non-zero if
# anything FAILs, so it is usable in CI.
#
# Implementation note: every loop reads from a process substitution rather than
# a pipe. `cmd | while read` runs the loop body in a SUBSHELL, so counter
# increments inside it are discarded and the exit status is always wrong — the
# first version of this script had exactly that bug.

set -uo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Package names declared by install.sh, used to decide whether a stray file in
# ~/.config belongs to this setup or to some unrelated app.
tools_list="$(mktemp)"
sed -n '/^PACKAGES_[A-Z]*=(/,/^)/p' "$REPO/install.sh" 2>/dev/null \
  | sed 's/#.*//' | tr ' ' '\n' \
  | grep -E '^[a-z0-9][a-z0-9._+-]*$' | sort -u > "$tools_list"
fails=0
warns=0

pass() { printf '  \033[32mok\033[0m      %s\n' "$1"; }
warn() { printf '  \033[33mwarn\033[0m    %s\n' "$1"; warns=$((warns+1)); }
fail() { printf '  \033[31mFAIL\033[0m    %s\n' "$1"; fails=$((fails+1)); }

# waybar accepts internal actions in on-click, not just commands. These are
# handled by waybar itself and are not binaries to look for.
is_waybar_action() {
  case "$1" in
    toggle|toggle_format|mode|reset|up|down|next|prev|play-pause|shift*) return 0 ;;
    *) return 1 ;;
  esac
}

# Strip leading option flags so `exec --no-startup-id foo` resolves to `foo`.
first_real_word() {
  local w
  for w in $1; do
    case "$w" in
      -*) continue ;;
      *)  printf '%s' "$w"; return ;;
    esac
  done
}

check_binary() {
  local bin="$1" origin="$2"
  [[ -z "$bin" ]] && return 0
  case "$bin" in
    ''|if|then|else|fi|exec|sh|bash|true|false|/*|~*|\$*|\{*) return 0 ;;
  esac
  is_waybar_action "$bin" && return 0
  if command -v "$bin" >/dev/null 2>&1; then
    pass "$bin  ($origin)"
  else
    fail "$bin NOT INSTALLED — referenced by $origin"
  fi
}

echo "==> Binaries referenced by waybar (on-click / on-scroll)"
while read -r cmd; do
  [[ "$cmd" == /* ]] && continue          # our own scripts, exercised below
  check_binary "$(first_real_word "$cmd")" "waybar config"
done < <(
  for f in "$CFG"/waybar/config-*; do
    [[ -r "$f" ]] || continue
    grep -oE '"on-(click|click-right|click-middle|scroll-up|scroll-down)"[[:space:]]*:[[:space:]]*"[^"]+"' "$f" 2>/dev/null \
      | sed -E 's/.*:[[:space:]]*"//; s/"$//'
  done | sort -u
)

echo "==> Binaries referenced by sway config (exec / exec_always)"
while read -r cmd; do
  [[ "$cmd" == /* || "$cmd" == '$'* ]] && continue
  check_binary "$(first_real_word "$cmd")" "sway/config"
done < <(
  { cat "$CFG/sway/config" 2>/dev/null; cat "$CFG"/sway/config.d/* 2>/dev/null; } \
    | grep -oE '^[[:space:]]*(exec|exec_always)[[:space:]]+.*' \
    | sed -E 's/^[[:space:]]*(exec|exec_always)[[:space:]]+//' \
    | sort -u
)

echo "==> waybar status modules produce usable output"
# Only scripts wired to a module's "exec" are status producers expected to
# print on stdout. Action scripts (btctl.sh, media-control.sh, the a2dp
# watchdog) legitimately print nothing when idle — checking them produced pure
# noise in the first version of this script.
while read -r s; do
  [[ -x "$s" ]] || continue
  name="$(basename "$s")"
  out="$(timeout 10 "$s" 2>/dev/null | head -1)"
  if [[ -z "$out" ]]; then
    # Not necessarily broken: modules with "hide-empty-text" (e.g.
    # custom/media-info with no player running) are SUPPOSED to print nothing.
    warn "$name produced no output (fine if its module sets hide-empty-text)"
  elif [[ "$out" == *'?'* ]]; then
    warn "$name output contains '?' (sensor unresolved): $out"
  else
    pass "$name -> $out"
  fi
done < <(
  for f in "$CFG"/waybar/config-*; do
    [[ -r "$f" ]] || continue
    grep -oE '"exec"[[:space:]]*:[[:space:]]*"[^"]+"' "$f" 2>/dev/null \
      | sed -E 's/.*:[[:space:]]*"//; s/"$//' \
      | sed -E 's/^exec[[:space:]]+//' | awk '{print $1}'
  done | sort -u | grep '\.sh$'
)

echo "==> icon-emitting scripts actually emit an icon"
# A dropped Nerd Font glyph renders as a bare space and is invisible in diffs.
# This is the check that would have caught the volume.sh regression on BOTH
# hosts. Nerd Font icons live in the Private Use Area, so require a non-ASCII
# byte in the output.
for name in volume.sh bluetooth-status.sh media-playpause.sh; do
  s="$CFG/waybar/scripts/$name"
  [[ -x "$s" ]] || continue
  out="$(timeout 10 "$s" 2>/dev/null | head -1)"
  if printf '%s' "$out" | LC_ALL=C grep -q '[^ -~]'; then
    pass "$name emits a glyph"
  else
    fail "$name emits NO glyph (icon lost?): '$out'"
  fi
done

echo "==> audio: fallback-sink names a real sink"
sinkfile="$CFG/waybar/fallback-sink"
if [[ ! -s "$sinkfile" ]]; then
  warn "fallback-sink unset (volume.sh recovery restarts wireplumber instead)"
else
  fb="$(cat "$sinkfile")"
  if [[ "$fb" == "auto_null" ]]; then
    fail "fallback-sink is 'auto_null' — PipeWire's dummy sink, not a real device"
  elif ! command -v wpctl >/dev/null 2>&1; then
    warn "wpctl absent; cannot validate fallback-sink '$fb'"
  elif wpctl status 2>/dev/null | grep -q "$fb"; then
    pass "fallback-sink = $fb"
  else
    warn "fallback-sink '$fb' not in wpctl status (stale — sink renamed?)"
  fi
fi

echo "==> audio: capture actually produces samples"
# A capture device can enumerate, open, and stream the right number of frames
# while delivering nothing but zeros -- that is exactly the state specter's
# internal microphones are in. Every layer above (wpctl, arecord's exit status,
# a meter in a GUI) reports success, so silence is invisible unless the samples
# are inspected. Record briefly and look at the actual values.
if ! command -v arecord >/dev/null 2>&1; then
  warn "arecord absent; cannot verify capture"
elif ! arecord -l 2>/dev/null | grep -q '^card'; then
  warn "no capture devices at all"
else
  capwav="$(mktemp -t doctor-cap-XXXXXX.wav)"
  if timeout 8 arecord -f S16_LE -r 48000 -c 2 -d 2 "$capwav" >/dev/null 2>&1 \
     && [[ -s "$capwav" ]]; then
    peak="$(python3 - "$capwav" <<'PY' 2>/dev/null || echo err
import sys, wave, struct
w = wave.open(sys.argv[1])
raw = w.readframes(w.getnframes())
s = struct.unpack("<%dh" % (len(raw) // 2), raw)
print(max((abs(x) for x in s), default=0))
PY
)"
    case "$peak" in
      err|"") warn "could not measure capture level" ;;
      0)      fail "capture returns digital silence (peak=0) — mic is routed but dead" ;;
      *)      pass "capture produces signal (peak=$peak)" ;;
    esac
  else
    warn "capture device would not open"
  fi
  rm -f "$capwav"
fi

echo "==> Nerd Font available to waybar"
nerd_count="$(fc-list 2>/dev/null | grep -ci 'nerd font' || true)"
if [[ "${nerd_count:-0}" -gt 0 ]]; then
  pass "Nerd Font present ($nerd_count faces)"
else
  fail "no Nerd Font — every bar icon renders as a box"
fi

echo "==> shell rc: tools guarded by 'command -v' are installed"
# The rc files wrap optional tools in `command -v X >/dev/null && ...`, so a
# missing tool degrades SILENTLY. starship went missing on specter exactly this
# way: the prompt fell back to plain bash with no error anywhere, which reads as
# "the dotfiles are broken" rather than "one package is absent". Derived from
# the rc files themselves so it cannot fall behind them.
while IFS= read -r tool; do
  [[ -z "$tool" ]] && continue
  if command -v "$tool" >/dev/null 2>&1; then
    pass "$tool"
  else
    warn "$tool absent — rc files fall back silently without it"
  fi
done < <(
  cat "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.xonshrc" 2>/dev/null \
    | grep -oE 'command -v [A-Za-z0-9_.+-]+' | awk '{print $3}' | sort -u
)

echo "==> configs install.sh links are symlinks to this repo (drift check)"
# Derived from install.sh's own `link` calls instead of a hardcoded list, so it
# cannot fall behind as the repo grows. wraith predates install.sh and has REAL
# directories under ~/.config, which is how the volume.sh glyph fix could be
# committed and still not reach the machine it was authored from.
while IFS='|' read -r rel dst; do
  [[ -z "$rel" || -z "$dst" ]] && continue
  src="$REPO/$rel"
  tgt="$HOME/$dst"
  [[ -e "$src" ]] || continue
  if [[ ! -e "$tgt" && ! -L "$tgt" ]]; then
    warn "$dst not present — install.sh has not been run here"
  elif [[ -L "$tgt" && "$(readlink -f "$tgt")" == "$(readlink -f "$src")" ]]; then
    pass "$dst"
  else
    warn "$dst is host-local, NOT a symlink — repo changes will not reach this host"
  fi
done < <(
  grep -E '^[[:space:]]*link "\$REPO/' "$REPO/install.sh" 2>/dev/null \
    | sed -E 's/^[[:space:]]*link[[:space:]]+"\$REPO\/([^"]+)"[[:space:]]+"\$HOME\/([^"]+)".*/\1|\2/' \
    | grep -v '\$'
)

echo "==> host-local config the repo does not track"
# starship.toml lived only on wraith for four months, so every other host
# silently got upstream defaults and a different prompt. A config named after a
# tool this setup installs, sitting in ~/.config but not linked into the repo,
# exists on exactly one machine — surface it before it becomes the next drift.
# Tool names come from install.sh's own package arrays, so this self-maintains.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  base="${f%%.*}"
  grep -qxF "$base" "$tools_list" || continue
  t="$CFG/$f"
  [[ -L "$t" && "$(readlink -f "$t")" == "$REPO"/* ]] && { pass "$f -> repo"; continue; }
  # If the repo already carries this file, the drift check above owns it and
  # reporting it again here would just double-count the same problem. Only flag
  # files the repo has never heard of — the genuine blind spot.
  if find "$REPO/config" "$REPO/home" -name "$f" -print -quit 2>/dev/null | grep -q .; then
    continue
  fi
  warn "$f is host-local and NOT in the repo — it exists on this machine only"
done < <(find "$CFG" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null \
           | grep -vE '\.bak(\.|$)' | sort)
rm -f "$tools_list"

echo
if (( fails )); then
  printf '\033[31m%d check(s) FAILED\033[0m, %d warning(s)\n' "$fails" "$warns"
  exit 1
fi
printf '\033[32mAll checks passed\033[0m (%d warning(s))\n' "$warns"
