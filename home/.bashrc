# ~/.bashrc

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# ble.sh — fish-like input line (autosuggest, syntax highlight, better completion).
# Optional: only loads if installed. `--noattach` defers init until the rc finishes;
# the matching `ble-attach` at the bottom turns it on after everything else.
[[ $- == *i* && -f /usr/share/blesh/ble.sh ]] && source /usr/share/blesh/ble.sh --noattach

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
    # any other eza flags pass through (depth defaults to 2 if no number given)
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
# Not aliasing du/ps — dust and procs have incompatible CLIs.
alias top='btop'
alias htop='btop'
# ssh handled by ~/.local/bin/ssh — smart wrapper for kitten/plain.
alias kssh='kitten ssh'

# bat as colored man pager
export MANROFFOPT="-c"
export GROFF_NO_SGR=1
export MANPAGER="sh -c 'col -bxp | bat -l man -p'"

# zoxide — `z <partial>` jumps to "frecent" directories
eval "$(zoxide init bash)"

# fzf key bindings (Ctrl+R history search, Ctrl+T file picker, Alt+C cd into dir)
[[ -f /usr/share/fzf/key-bindings.bash ]] && source /usr/share/fzf/key-bindings.bash
[[ -f /usr/share/fzf/completion.bash ]] && source /usr/share/fzf/completion.bash

# Attach ble.sh now that setup is done (paired with --noattach at top).
[[ ${BLE_VERSION-} ]] && ble-attach
