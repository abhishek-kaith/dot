# ~/.zshenv: read by EVERY zsh, including the non-interactive ones that
# scripts and AI agents start. Keep it tiny and silent: no output, no aliases,
# no prompt, nothing slow. Interactive config lives in ~/.config/zsh/.zshrc.

export ZDOTDIR="$HOME/.config/zsh"

# Same PATH as the desktop session (~/.config/environment.d/10-env.conf), so a
# tty login or ssh session finds the same tools. typeset -U drops duplicates.
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/.local/share/mise/shims" $path)

export EDITOR=nvim VISUAL=nvim
