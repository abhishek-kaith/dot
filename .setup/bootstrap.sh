#!/bin/sh
# Fresh machine: clone the dotfiles into $HOME as a bare repo, then run install.
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/abhishek-kaith/dot/main/.setup/bootstrap.sh)" -- kde
set -eu

de=${1:-kde}
repo=https://github.com/abhishek-kaith/dot.git
git() { command git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" "$@"; }

command -v git >/dev/null || sudo pacman -S --needed git

if [ ! -d "$HOME/.dotfiles" ]; then
    command git clone --bare "$repo" "$HOME/.dotfiles"
fi
git config status.showUntrackedFiles no
# commits to this public repo use GitHub's private noreply address, not your real email
git config user.name abhishek-kaith
git config user.email 62424903+abhishek-kaith@users.noreply.github.com

# Files the repo would overwrite are moved to ~/.dotfiles-backup first.
if ! git checkout 2>/dev/null; then
    backup="$HOME/.dotfiles-backup"
    echo "moving existing files to $backup"
    git checkout 2>&1 | awk '/^[[:space:]]/ {print $1}' | while read -r f; do
        mkdir -p "$backup/$(dirname "$f")"
        mv "$HOME/$f" "$backup/$f"
    done
    git checkout
fi

exec "$HOME/.setup/install.sh" "$de"
