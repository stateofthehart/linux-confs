#!/usr/bin/env bash
# cli-install.sh — install enhanced CLI tools and append aliases/init to a shell rc.
#
# Usage:
#   ./cli-install.sh --bash       # install + append to ~/.bashrc
#   ./cli-install.sh --xonsh      # install + append to ~/.xonshrc
#   ./cli-install.sh --bash --no-install   # only modify rc (skip pkg install)
#   ./cli-install.sh --bash --icons=always --starship=always
#
# Idempotent: re-running replaces the previously-appended block.
# Targets pacman (Arch). On apt/dnf it tries best-effort; package names differ
# (bat→batcat, fd→fdfind on Debian) and you may need to tweak.

set -euo pipefail

SHELL_KIND=""
DO_INSTALL=1
ICON_MODE=always
STARSHIP_MODE=always

for arg in "$@"; do
    case "$arg" in
        --bash)        SHELL_KIND=bash ;;
        --xonsh)       SHELL_KIND=xonsh ;;
        --no-install)  DO_INSTALL=0 ;;
        --icons=auto|--icons=always|--icons=never)
                       ICON_MODE="${arg#--icons=}" ;;
        --icons)       ICON_MODE=always ;;
        --no-icons)    ICON_MODE=never ;;
        --icons=*)     echo "invalid --icons mode: ${arg#--icons=} (use auto, always, or never)" >&2; exit 1 ;;
        --starship=auto|--starship=always|--starship=never)
                       STARSHIP_MODE="${arg#--starship=}" ;;
        --starship)    STARSHIP_MODE=always ;;
        --no-starship) STARSHIP_MODE=never ;;
        --starship=*)  echo "invalid --starship mode: ${arg#--starship=} (use auto, always, or never)" >&2; exit 1 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *) echo "unknown arg: $arg" >&2; exit 1 ;;
    esac
done

[[ -n "$SHELL_KIND" ]] || { echo "Specify --bash or --xonsh (use -h for help)" >&2; exit 1; }

EZA_ICON_ARGS=""
ICON_STATUS=""
STARSHIP_STATUS=""
STARSHIP_INIT_BASH=""
STARSHIP_INIT_XONSH=""

configure_rendering() {
    case "$ICON_MODE" in
        always)
            EZA_ICON_ARGS="--icons=always "
            ICON_STATUS="always (requested)"
            ;;
        never)
            ICON_STATUS="disabled (requested)"
            ;;
        auto)
            EZA_ICON_ARGS="--icons=auto "
            ICON_STATUS="auto (eza decides at runtime)"
            ;;
    esac

    case "$STARSHIP_MODE" in
        always)
            STARSHIP_STATUS="always (requested)"
            ;;
        never)
            STARSHIP_STATUS="disabled (requested)"
            ;;
        auto)
            STARSHIP_STATUS="auto (enabled when starship is installed)"
            ;;
    esac

    if [[ "$STARSHIP_STATUS" == disabled* ]]; then
        STARSHIP_INIT_BASH="# starship disabled by cli-install: $STARSHIP_STATUS"
        STARSHIP_INIT_XONSH="# starship disabled by cli-install: $STARSHIP_STATUS"
    else
        STARSHIP_INIT_BASH=$'if command -v starship >/dev/null 2>/dev/null; then\n    eval "$(starship init bash)"\nfi'
        STARSHIP_INIT_XONSH=$'if _cli_install_sh.which("starship"):\n    xontrib load prompt_starship'
    fi
}

configure_rendering

select_utf8_locale() {
    local loc
    for loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
        if [[ "$(LC_ALL="$loc" locale charmap 2>/dev/null || true)" =~ [Uu][Tt][Ff]-?8 ]]; then
            echo "$loc"
            return 0
        fi
    done
    return 1
}

#### --- Package install ---------------------------------------------------

detect_pm() {
    if command -v pacman >/dev/null 2>&1;  then echo pacman
    elif command -v apt-get >/dev/null 2>&1; then echo apt
    elif command -v dnf >/dev/null 2>&1;     then echo dnf
    else echo none
    fi
}

# Fetch a static Linux binary from a GitHub project's latest release.
# Args: <repo> <asset_url_filter> <binary_name>
# Idempotent: returns 0 if the binary is already on PATH.
# Used to fill gaps where a distro's repo doesn't ship a tool (Ubuntu 24.04
# noble lacks du-dust and procs; Fedora 44 lacks starship).
#
# The asset filter may contain the literal token %ARCH%, replaced with the
# release-naming form of the current machine. This used to hard-skip anything
# that wasn't x86_64, which silently left aarch64 hosts (e.g. the Snapdragon
# ThinkBook) with no starship/dust/procs at all. These projects all publish
# aarch64 assets; only the filename differs.
github_release_install() {
    local repo=$1 pattern=$2 binary=$3

    command -v "$binary" >/dev/null 2>&1 && return 0

    local gh_arch
    case "$(uname -m)" in
        x86_64)          gh_arch=x86_64  ;;
        aarch64|arm64)   gh_arch=aarch64 ;;
        *)
            echo "  $binary: no github asset naming known for $(uname -m)" >&2
            return 1
            ;;
    esac
    pattern=${pattern//%ARCH%/$gh_arch}

    echo "==> fetching $binary from github.com/$repo/releases/latest"
    local url
    url=$(curl -sL "https://api.github.com/repos/$repo/releases/latest" \
        | grep -oE "\"browser_download_url\": \"[^\"]*${pattern}[^\"]*\"" \
        | head -1 | cut -d'"' -f4)

    if [[ -z "$url" ]]; then
        echo "  $binary: no release asset matching '$pattern'" >&2
        return 1
    fi

    local tmp
    tmp=$(mktemp -d)
    case "$url" in
        *.tar.gz|*.tgz) curl -sL "$url" | tar -xz -C "$tmp" ;;
        *.zip)
            if ! command -v unzip >/dev/null 2>&1; then
                echo "  $binary: 'unzip' is required to extract this asset" >&2
                rm -rf "$tmp"; return 1
            fi
            curl -sLo "$tmp/asset.zip" "$url" && unzip -q "$tmp/asset.zip" -d "$tmp"
            ;;
        *) echo "  $binary: unsupported archive format $url" >&2; rm -rf "$tmp"; return 1 ;;
    esac

    local bin
    bin=$(find "$tmp" -type f -name "$binary" -executable 2>/dev/null | head -1)
    if [[ -z "$bin" ]]; then
        echo "  $binary: not found in extracted archive" >&2
        rm -rf "$tmp"; return 1
    fi

    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$bin" "$HOME/.local/bin/$binary"
    rm -rf "$tmp"
    echo "  $binary: installed to ~/.local/bin/$binary"
}

install_packages() {
    local pm
    pm=$(detect_pm)

    # Tools wanted on every machine. Names valid on pacman; apt/dnf vary.
    local pkgs=(bat eza fd ripgrep zoxide git-delta btop dust procs fzf tmux mosh starship)
    [[ "$SHELL_KIND" == xonsh ]] && pkgs+=(xonsh python-pip)

    case "$pm" in
        pacman)
            sudo pacman -S --needed --noconfirm "${pkgs[@]}" || true
            ;;
        apt)
            # Debian/Ubuntu package-name differences:
            #   dust  → du-dust   (avoids conflict with GNU du)
            #   fd    → fd-find   (binary becomes `fdfind`; we symlink below)
            #   bat   → bat       (binary may be `batcat` on older Debian; symlink below)
            #
            # IMPORTANT: split into two transactions because apt aborts the entire
            # transaction if any single package is missing. `du-dust` and `procs`
            # aren't in Ubuntu 24.04 (noble); putting them in their own batch
            # prevents that failure from taking down the rest of the install.
            sudo apt-get update
            echo "==> apt install (main batch — universe packages)"
            sudo apt-get install -y \
                bat eza fd-find ripgrep zoxide git-delta \
                btop fzf tmux mosh \
                curl unzip ca-certificates || true
            # These may not exist on older Ubuntu (noble lacks both) — github
            # fallback below installs them when the apt path fails.
            echo "==> apt install (optional — may be missing on older Ubuntu)"
            sudo apt-get install -y du-dust procs || true
            [[ "$SHELL_KIND" == xonsh ]] && sudo apt-get install -y xonsh python3-pip

            # Add ~/.local/bin shims for renamed binaries.
            mkdir -p "$HOME/.local/bin"
            if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
                ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
                echo "  symlinked fdfind → ~/.local/bin/fd"
            fi
            if ! command -v bat >/dev/null && command -v batcat >/dev/null; then
                ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
                echo "  symlinked batcat → ~/.local/bin/bat"
            fi
            ;;
        dnf)
            # Same split-batch logic as apt — dnf also aborts the transaction
            # on any missing package.
            sudo dnf install -y bat eza fd-find ripgrep zoxide git-delta \
                                btop fzf tmux mosh \
                                curl unzip ca-certificates || true
            sudo dnf install -y dust procs || true
            [[ "$SHELL_KIND" == xonsh ]] && sudo dnf install -y xonsh python3-pip
            ;;
        none)
            echo "WARN: no supported package manager — install the tools yourself" >&2
            ;;
    esac

    # Universal starship fallback (works on any distro without sudo).
    if ! command -v starship >/dev/null 2>&1; then
        echo "==> installing starship to ~/.local/bin"
        mkdir -p "$HOME/.local/bin"
        curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
    fi

    # Github-release fallbacks for tools missing from older distro repos.
    # These no-op if the binary is already on PATH.
    github_release_install bootandy/dust '%ARCH%-unknown-linux-gnu\.tar\.gz' dust  || true
    github_release_install dalance/procs '%ARCH%-linux\.zip'                procs || true

    # Standalone `kitten` binary so `kitten icat` works over SSH from a kitty
    # terminal. Avoids pulling the full `kitty` package (X11/GL deps) on servers.
    # kitty publishes both amd64 and arm64 kitten binaries; pick by machine.
    if ! command -v kitten >/dev/null 2>&1; then
        local kitten_arch=
        case "$(uname -m)" in
            x86_64)        kitten_arch=amd64 ;;
            aarch64|arm64) kitten_arch=arm64 ;;
        esac
        if [[ -n "$kitten_arch" ]]; then
            echo "==> installing kitten ($kitten_arch) to ~/.local/bin"
            mkdir -p "$HOME/.local/bin"
            curl -fsSL -o "$HOME/.local/bin/kitten" \
                "https://github.com/kovidgoyal/kitty/releases/latest/download/kitten-linux-${kitten_arch}" \
                && chmod +x "$HOME/.local/bin/kitten" \
                || echo "  kitten: download failed" >&2
        fi
    fi

    # Xontrib bridge for starship in xonsh (no native xonsh support upstream).
    if [[ "$SHELL_KIND" == xonsh ]]; then
        if command -v xpip >/dev/null 2>&1; then
            xpip install --user --break-system-packages --quiet xontrib-prompt-starship || true
        elif command -v pip >/dev/null 2>&1; then
            pip install --user --break-system-packages --quiet xontrib-prompt-starship || true
        fi
    fi
}

#### --- Git/delta config --------------------------------------------------

configure_git_delta() {
    command -v delta >/dev/null 2>&1 || return 0
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
    git config --global delta.line-numbers true
    git config --global delta.side-by-side true
    git config --global merge.conflictstyle diff3
    git config --global diff.colorMoved default
}

#### --- Per-shell rc blocks -----------------------------------------------

BASH_BLOCK=$(cat <<'EOF'
# === cli-install: enhanced terminal aliases ===
# (Managed by cli-install.sh — re-run to update; do not edit between markers.)
# Many tools installed by cli-install.sh land in ~/.local/bin (starship, dust,
# procs, kitten, fd/bat symlinks). Distros vary on whether login shells add
# this to PATH; ensure it's there regardless.
# eza icons: __CLI_INSTALL_ICON_STATUS__
# starship: __CLI_INSTALL_STARSHIP_STATUS__
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
_cli_install_charmap=$(locale charmap 2>/dev/null || true)
if [[ ! "$_cli_install_charmap" =~ [Uu][Tt][Ff]-?8 ]]; then
    for _cli_install_locale in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
        if [[ "$(LC_ALL="$_cli_install_locale" locale charmap 2>/dev/null || true)" =~ [Uu][Tt][Ff]-?8 ]]; then
            export LANG="$_cli_install_locale"
            export LC_CTYPE="$_cli_install_locale"
            unset LC_ALL
            break
        fi
    done
fi
unset _cli_install_charmap _cli_install_locale
if command -v eza >/dev/null 2>&1; then
    alias ls='eza __EZA_ICON_ARGS__--git --group-directories-first'
    alias ll='eza __EZA_ICON_ARGS__--git --group-directories-first -lh'
    alias la='eza __EZA_ICON_ARGS__--git --group-directories-first -lah'
    lt() {
        # lt | lt 4 | lt 4 ~/src | lt --level=N (any depth)
        if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
            eza __EZA_ICON_ARGS__--git --tree --level="$1" "${@:2}"
        else
            eza __EZA_ICON_ARGS__--git --tree --level=2 "$@"
        fi
    }
else
    alias ll='ls -lh'
    alias la='ls -lah'
    lt() {
        local depth=2
        if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
            depth="$1"
            shift
        fi
        if [[ $# -eq 0 ]]; then
            find . -maxdepth "$depth" -print
        else
            find "$@" -maxdepth "$depth" -print
        fi
    }
fi
alias grep='grep --color=auto'
# Interactive-only replacements. Not aliasing du/ps — dust/procs have incompatible CLIs.
if command -v btop >/dev/null 2>&1; then
    alias top='btop'
    alias htop='btop'
fi
if command -v tmux >/dev/null 2>&1; then
    alias tmux='tmux -u'
fi
export MANROFFOPT="-c"
export GROFF_NO_SGR=1
if command -v bat >/dev/null 2>&1; then
    export MANPAGER="sh -c 'col -bxp | bat -l man -p'"
elif command -v batcat >/dev/null 2>&1; then
    export MANPAGER="sh -c 'col -bxp | batcat -l man -p'"
fi
__CLI_INSTALL_STARSHIP_INIT_BASH__
command -v zoxide   >/dev/null 2>&1 && eval "$(zoxide init bash)"
for _cli_install_fzf_file in \
    /usr/share/fzf/key-bindings.bash \
    /usr/share/doc/fzf/examples/key-bindings.bash
do
    [[ -f "$_cli_install_fzf_file" ]] && source "$_cli_install_fzf_file" && break
done
for _cli_install_fzf_file in \
    /usr/share/fzf/completion.bash \
    /usr/share/doc/fzf/examples/completion.bash
do
    [[ -f "$_cli_install_fzf_file" ]] && source "$_cli_install_fzf_file" && break
done
unset _cli_install_fzf_file
# === /cli-install ===
EOF
)

BASH_BLOCK=${BASH_BLOCK//__EZA_ICON_ARGS__/$EZA_ICON_ARGS}
BASH_BLOCK=${BASH_BLOCK//__CLI_INSTALL_ICON_STATUS__/$ICON_STATUS}
BASH_BLOCK=${BASH_BLOCK//__CLI_INSTALL_STARSHIP_STATUS__/$STARSHIP_STATUS}
BASH_BLOCK=${BASH_BLOCK//__CLI_INSTALL_STARSHIP_INIT_BASH__/$STARSHIP_INIT_BASH}

TMUX_BLOCK=$(cat <<'EOF'
# === cli-install: enhanced terminal aliases ===
# (Managed by cli-install.sh — re-run to update; do not edit between markers.)
# Allow kitty's graphics protocol (icat etc.) to pass through tmux to the
# parent kitty terminal. Required for icat to render images inside tmux.
set -g default-terminal "tmux-256color"
set -g update-environment "DISPLAY KRB5CCNAME SSH_ASKPASS SSH_AUTH_SOCK SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY LANG LC_ALL LC_CTYPE LC_COLLATE LC_MESSAGES COLORTERM NO_COLOR TERM_PROGRAM"
set -g allow-passthrough on
# === /cli-install ===
EOF
)

XONSH_BLOCK=$(cat <<'EOF'
# === cli-install: enhanced terminal aliases ===
# (Managed by cli-install.sh — re-run to update; do not edit between markers.)
import os as _cli_install_os
import shutil as _cli_install_sh
_cli_install_local_bin = _cli_install_os.path.expanduser("~/.local/bin")
if _cli_install_local_bin not in $PATH:
    $PATH.insert(0, _cli_install_local_bin)
# eza icons: __CLI_INSTALL_ICON_STATUS__
# starship: __CLI_INSTALL_STARSHIP_STATUS__
if _cli_install_sh.which("eza"):
    aliases["ls"] = "eza __EZA_ICON_ARGS__--git --group-directories-first"
    aliases["ll"] = "eza __EZA_ICON_ARGS__--git --group-directories-first -lh"
    aliases["la"] = "eza __EZA_ICON_ARGS__--git --group-directories-first -lah"
    def _lt(args):
        # lt | lt 4 | lt 4 ~/src | lt --level=N
        depth = "2"
        rest = list(args)
        if rest and rest[0].isdigit():
            depth = rest.pop(0)
        $[eza __EZA_ICON_ARGS__--git --tree --level=@(depth) @(rest)]
    aliases["lt"] = _lt
else:
    aliases["ll"] = "ls -lh"
    aliases["la"] = "ls -lah"
    def _lt(args):
        depth = "2"
        rest = list(args)
        if rest and rest[0].isdigit():
            depth = rest.pop(0)
        if not rest:
            rest = ["."]
        $[find @(rest) -maxdepth @(depth) -print]
    aliases["lt"] = _lt
aliases["grep"] = "grep --color=auto"
# Interactive-only. Not aliasing du/ps — dust/procs have incompatible CLIs.
if _cli_install_sh.which("btop"):
    aliases["top"] = "btop"
    aliases["htop"] = "btop"
if _cli_install_sh.which("tmux"):
    aliases["tmux"] = "tmux -u"
$MANROFFOPT = "-c"
$GROFF_NO_SGR = "1"
if _cli_install_sh.which("bat"):
    $MANPAGER = "sh -c 'col -bxp | bat -l man -p'"
elif _cli_install_sh.which("batcat"):
    $MANPAGER = "sh -c 'col -bxp | batcat -l man -p'"
__CLI_INSTALL_STARSHIP_INIT_XONSH__
if _cli_install_sh.which("zoxide"):
    execx($(zoxide init xonsh), "exec", __xonsh__.ctx, filename="zoxide")
# === /cli-install ===
EOF
)

XONSH_BLOCK=${XONSH_BLOCK//__EZA_ICON_ARGS__/$EZA_ICON_ARGS}
XONSH_BLOCK=${XONSH_BLOCK//__CLI_INSTALL_ICON_STATUS__/$ICON_STATUS}
XONSH_BLOCK=${XONSH_BLOCK//__CLI_INSTALL_STARSHIP_STATUS__/$STARSHIP_STATUS}
XONSH_BLOCK=${XONSH_BLOCK//__CLI_INSTALL_STARSHIP_INIT_XONSH__/$STARSHIP_INIT_XONSH}

#### --- Append/replace block in rc file -----------------------------------

write_block() {
    local rc=$1 block=$2
    local marker_start="# === cli-install: enhanced terminal aliases ==="
    local marker_end="# === /cli-install ==="

    # This script is meant for bare remote hosts. On a host provisioned by
    # install.sh, ~/.bashrc is a SYMLINK into the linux-confs checkout, and
    # writing here would edit a tracked file through the link -- appending
    # repo content on the remote, or (via the update path below) replacing the
    # symlink with a regular file and silently detaching the host from the
    # repo. The repo's own rc already sets up starship/eza/zoxide, so the block
    # is redundant there anyway. Refuse, and say what to run instead.
    if [[ -L "$rc" ]]; then
        local target; target=$(readlink -f "$rc")
        if [[ "$target" == *"/linux-confs/"* ]]; then
            echo "==> $rc is a symlink into linux-confs ($target)" >&2
            echo "    skipping rc edit — that file is version-controlled and already" >&2
            echo "    configures the prompt. Run install.sh on this host instead;" >&2
            echo "    cli-install.sh has still installed the binaries above." >&2
            return 0
        fi
    fi

    touch "$rc"

    if grep -qF "$marker_start" "$rc"; then
        local tmp; tmp=$(mktemp)
        awk -v s="$marker_start" -v e="$marker_end" '
            $0 == s { skip=1; next }
            skip && $0 == e { skip=0; next }
            !skip
        ' "$rc" > "$tmp"
        # Write THROUGH any symlink rather than `mv` over it, which would
        # replace the link with a plain file.
        cat "$tmp" > "$rc"
        rm -f "$tmp"
        echo "==> updated existing block in $rc"
    else
        echo "==> appending block to $rc"
    fi
    printf '\n%s\n' "$block" >> "$rc"
}

print_rendering_report() {
    echo "==> Rendering choices"
    echo "  eza icons: $ICON_STATUS"
    echo "  starship:  $STARSHIP_STATUS"
    if [[ "$ICON_STATUS" == disabled* ]]; then
        echo "  tip: re-run with --icons=always if your terminal uses a Nerd Font"
    fi
    if [[ "$STARSHIP_STATUS" == disabled* ]]; then
        echo "  tip: re-run with --starship=always to enable the Starship prompt"
    fi
}

refresh_tmux_server() {
    command -v tmux >/dev/null 2>&1 || return 0
    tmux has-session >/dev/null 2>&1 || return 0

    tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1 || true

    local utf8_locale
    utf8_locale=$(select_utf8_locale || true)
    if [[ -n "$utf8_locale" ]]; then
        tmux set-environment -g LANG "$utf8_locale" >/dev/null 2>&1 || true
        tmux set-environment -g LC_CTYPE "$utf8_locale" >/dev/null 2>&1 || true
        tmux set-environment -gu LC_ALL >/dev/null 2>&1 || true
    fi
}

#### --- Main --------------------------------------------------------------

main() {
    if [[ $DO_INSTALL -eq 1 ]]; then
        install_packages
        configure_git_delta
    fi

    case "$SHELL_KIND" in
        bash)  write_block "$HOME/.bashrc"  "$BASH_BLOCK" ;;
        xonsh) write_block "$HOME/.xonshrc" "$XONSH_BLOCK" ;;
    esac
    write_block "$HOME/.tmux.conf" "$TMUX_BLOCK"
    refresh_tmux_server
    print_rendering_report

    echo
    echo "Done. Open a new shell or 'source ~/.${SHELL_KIND}rc' to pick up changes."
}

main "$@"
