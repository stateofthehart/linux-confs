# ~/.bashrc

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# ssh-agent: one agent per user session, reached through a FIXED socket path.
#
# The old `eval "$(ssh-agent -s)"` ran unconditionally and leaked a brand-new
# agent process for every interactive shell — dozens accumulate over a session.
# Checking SSH_AUTH_SOCK alone doesn't help: each new shell starts without it
# and would spawn its own agent anyway. A fixed socket is what makes the agent
# discoverable across shells.
#
# `ssh-add -l` exit codes: 0 = agent has keys, 1 = agent up but empty,
# 2 = cannot reach an agent. Only 2 means we need to start one.
_agent_reachable() { ssh-add -l >/dev/null 2>&1; [ $? -ne 2 ]; }

if ! _agent_reachable; then
    # Nothing inherited (and nothing forwarded in over SSH) — use our own.
    export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket"
    if ! _agent_reachable; then
        rm -f "$SSH_AUTH_SOCK"
        ssh-agent -a "$SSH_AUTH_SOCK" >/dev/null 2>&1
    fi
fi
unset -f _agent_reachable
for _key in "$HOME/.ssh/farmgpu-shared-team"; do
    [ -f "$_key" ] && ssh-add -q "$_key" 2>/dev/null
done
unset _key

# ble.sh — fish-like input line: autosuggestions, syntax highlighting, completion menu.
# `--noattach` defers initialization so the rest of this rc runs first; the matching
# `ble-attach` at the bottom of the file activates it after everything else is set up.
# NOT packaged on Fedora (Arch has `blesh`); guard the source so its absence is
# silent instead of an error on every shell. Install from github.com/akinomyoga/ble.sh
[[ $- == *i* ]] && [[ -r /usr/share/blesh/ble.sh ]] && source /usr/share/blesh/ble.sh --noattach

# Basic PATH
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# History
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend
shopt -s checkwinsize

# Prompt: starship if available, fallback to plain.
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
else
    PS1='\u@\h:\w\$ '
fi

# Aliases — eza replaces ls
alias ls='eza --icons --git --group-directories-first'
alias ll='eza --icons --git --group-directories-first -lh'
alias la='eza --icons --git --group-directories-first -lah'
lt() {
    # lt          → tree, depth 2
    # lt 4        → tree, depth 4
    # lt 4 ~/src  → tree, depth 4, in ~/src
    # lt --level=5 / any other eza flags pass through (depth defaults to 2)
    if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
        eza --icons --git --tree --level="$1" "${@:2}"
    else
        eza --icons --git --tree --level=2 "$@"
    fi
}
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# Drop-in replacements for interactive use (scripts unaffected).
# Note: NOT aliasing du/ps — dust and procs have incompatible CLIs (no -sh, etc).
# Use `dust` and `procs` by name when you want them.
alias top='btop'
alias htop='btop'
# ssh handled by ~/.local/bin/ssh — smart wrapper for kitten/plain.
alias kssh='kitten ssh'

# bat as colored man pager.
# - GROFF_NO_SGR / MANROFFOPT: ask groff not to emit ANSI escapes (plain output)
# - col -bxp:  -p preserves any escapes that did slip through (instead of stripping ESC)
# - bat -l man -p: syntax-highlights the resulting plain text as a man page
export MANROFFOPT="-c"
export GROFF_NO_SGR=1
export MANPAGER="sh -c 'col -bxp | bat -l man -p'"

# zoxide — `z <partial>` jumps to "frecent" directories
eval "$(zoxide init bash)"

# fzf key bindings (Ctrl+R history search, Ctrl+T file picker, Alt+C cd into dir)
[[ -f /usr/share/fzf/key-bindings.bash ]] && source /usr/share/fzf/key-bindings.bash
[[ -f /usr/share/fzf/completion.bash ]] && source /usr/share/fzf/completion.bash

# Attach ble.sh now that all setup is done (paired with --noattach at top).
[[ ${BLE_VERSION-} ]] && ble-attach

# ssh host tab-completion from the NetBox /etc/hosts block + ~/.ssh/config aliases.
# Bare hostnames only (the .fgpu aliases stay in /etc/hosts — they're load-bearing
# for canonicalization — but we don't offer them as completions). Registered AFTER
# ble-attach / bash-completion so this compspec wins and nothing re-injects .fgpu.
# e.g. `ssh po<TAB>` -> potato01 potato02 ...
_fleet_hosts() {
  {
    awk '/BEGIN netbox-hosts/{f=1;next} /END netbox-hosts/{f=0} f {print $3}' /etc/hosts 2>/dev/null
    awk '/^[Hh]ost[ \t]/{for(i=2;i<=NF;i++) if($i !~ /[*?!]/) print $i}' ~/.ssh/config 2>/dev/null
  } | sort -u
}
_ssh_fleet_complete() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=( $(compgen -W "$(_fleet_hosts)" -- "$cur") )
}
complete -F _ssh_fleet_complete ssh

alias netcheck='ping -c 5 8.8.8.8'
alias lssh='kssh -o StrictHostKeyChecking=no'
alias prusa='GDK_BACKEND=x11 prusa-slicer'

alias dmount='udisksctl mount -b $1'
dumount() {
	echo "Unmounting $1";
	udisksctl unmount -b $1;
	echo "Powering off $1";
	udisksctl power-off -b $1;
}

alias unclaude='claude --dangerously-skip-permissions'
export PATH="$HOME/.cargo/bin:$PATH"
# Flatpak-installed apps put their launchers here. Fedora's shell profile only
# adds this for login shells, so without it `flatpak run`-less invocation (e.g.
# `google-chrome-stable`) fails in an interactive non-login shell.
export PATH="$PATH:/var/lib/flatpak/exports/bin"
