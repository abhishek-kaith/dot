# ~/.config/zsh/.zshrc: interactive shells only.
# Plugins come from pacman (no plugin manager). Edit, then `exec zsh`.

# ── history ──────────────────────────────────────────────────────────
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=50000
SAVEHIST=50000
[[ -d ${HISTFILE:h} ]] || mkdir -p "${HISTFILE:h}"
setopt share_history hist_ignore_all_dups hist_ignore_space hist_reduce_blanks
setopt extended_history auto_cd interactive_comments no_beep

# ── completion ───────────────────────────────────────────────────────
zcache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d $zcache ]] || mkdir -p "$zcache"
autoload -Uz compinit && compinit -d "$zcache/zcompdump"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' cache-path "$zcache"
unset zcache

# ── keys (vi mode) ───────────────────────────────────────────────────
bindkey -v
KEYTIMEOUT=1
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey -s '^f' 'tmux-sessionizer\n'

# ── aliases ──────────────────────────────────────────────────────────
# dotfiles: a bare git repo with $HOME as work tree. Keep `dot` an ALIAS (not
# a function): zsh expands aliases before completing, so `dot add <Tab>` gets
# full git completion against the right repo.
alias dot='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
alias lazydot='lazygit --git-dir=$HOME/.dotfiles --work-tree=$HOME'

alias ls='eza --icons=auto --group-directories-first'
alias ll='eza -l --icons=auto --git --group-directories-first'
alias la='eza -la --icons=auto --git --group-directories-first'
alias lt='eza --tree --level=2 --icons=auto'
alias vim='nvim'
alias g='git'
alias lg='lazygit'

# bat/delta use the terminal's own 16 colours, so they follow light/dark.
export BAT_THEME=ansi

# ── tools ────────────────────────────────────────────────────────────
# fzf: Ctrl+R history, Ctrl+T files, Alt+C cd (after bindkey -v on purpose)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
source <(fzf --zsh)
eval "$(zoxide init zsh)"      # z <part-of-dir>
eval "$(starship init zsh)"

# mise: tools resolve through the shims on PATH (see ~/.zshenv), which also
# work in non-interactive shells. No `mise activate` hook needed.

# ── plugins (keep syntax-highlighting last) ──────────────────────────
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
