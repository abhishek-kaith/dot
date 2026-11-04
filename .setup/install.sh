#!/bin/sh
# Set up this machine after a minimal archinstall.
#   ~/.setup/install.sh kde      or      ~/.setup/install.sh gnome
# Safe to re-run: every step skips what is already done.
set -eu

de=${1:-}
case $de in
    kde) dm=plasmalogin.service ;;
    gnome) dm=gdm.service ;;
    *) echo "usage: $0 kde|gnome" >&2; exit 1 ;;
esac

dir=$(cd "$(dirname "$0")" && pwd)
host=$(cat /etc/hostname)
rebuild=0

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
list() { sed 's/#.*//' "$@" | tr -s ' \t' '\n' | grep -v '^$'; }

# Add a kernel option to /etc/kernel/cmdline, which mkinitcpio bakes into the
# unified kernel image; the image is rebuilt once at the end. Safe to repeat:
# an option already present is skipped. The untouched original is kept as
# /etc/kernel/cmdline.orig. Undo: remove the word, then `sudo mkinitcpio -P`.
kernel_param() {
    if [ ! -f /etc/kernel/cmdline ]; then
        echo "!! no /etc/kernel/cmdline: add '$1' to your boot entry by hand"
        return 0
    fi
    grep -qw -- "$1" /etc/kernel/cmdline && return 0
    [ -f /etc/kernel/cmdline.orig ] || sudo cp /etc/kernel/cmdline /etc/kernel/cmdline.orig
    sudo sed -i "1s|\$| $1|" /etc/kernel/cmdline
    echo "kernel option added: $1"
    echo "  now: $(cat /etc/kernel/cmdline)"
    rebuild=1
}

# Let TRIM through LUKS2, stored in the header (Arch wiki: dm-crypt/Specialties).
luks_discard() {
    name=$1
    dev=$(sudo cryptsetup status "$name" 2>/dev/null | awk '$1 == "device:" {print $2}')
    [ -n "$dev" ] || return 0
    sudo cryptsetup luksDump "$dev" | grep -q '^Version:[[:space:]]*2' || return 0
    sudo cryptsetup luksDump "$dev" | grep -q allow-discards && return 0
    echo "enabling TRIM on LUKS device '$name' (asks for the disk passphrase)"
    sudo cryptsetup --allow-discards --persistent refresh "$name"
}

say "packages: common + $de"
# shellcheck disable=SC2046  # word splitting is wanted: one word per package
sudo pacman -S --needed $(list "$dir/common.txt" "$dir/$de.txt")

# AUR packages (not checked by Arch: read each PKGBUILD before adding one).
# yay-bin is built once with makepkg; afterwards `yay -Syu` updates and
# rebuilds them with the rest of the system. git and base-devel come from common.txt.
if [ -f "$dir/$de-aur.txt" ]; then
    say "AUR: $de"
    if ! command -v yay >/dev/null; then
        tmp=$(mktemp -d)
        git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi
    # shellcheck disable=SC2046
    yay -S --needed $(list "$dir/$de-aur.txt")
fi

say "flatpak"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if [ "$de" = kde ]; then theme=org.gtk.Gtk3theme.Breeze; else theme="org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark"; fi
# shellcheck disable=SC2046,SC2086
flatpak install --user --noninteractive flathub $(list "$dir/flatpak.txt") $theme

# qBittorrent: fixed port 51413 (allowed in ufw below). Only a starting config;
# never overwrites one that exists.
[ -e "$HOME/.config/qBittorrent/qBittorrent.conf" ] ||
    install -Dm600 "$dir/qBittorrent.conf" "$HOME/.config/qBittorrent/qBittorrent.conf"

say "mise tools"
mise install

say "zram (Arch wiki values for in-memory swap)"
[ -f /etc/systemd/zram-generator.conf ] || printf '[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd\n' |
    sudo tee /etc/systemd/zram-generator.conf >/dev/null
sudo tee /etc/sysctl.d/99-zram.conf >/dev/null <<'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
sudo sysctl -q --system

say "SSD TRIM"
root=$(findmnt -no SOURCE /)
luks_discard "${root#/dev/mapper/}"

say "services"
sudo systemctl enable --now bluetooth.service cups.socket fstrim.timer paccache.timer reflector.timer
# Keep a login screen that is already set up; only enable one on a fresh install.
[ -e /etc/systemd/system/display-manager.service ] || sudo systemctl enable "$dm"
# Except SDDM on KDE (archinstall's pick): its X11 greeter leaves an Xorg running
# after login, which keeps the NVIDIA GPU awake. Plasma Login Manager is Wayland.
if [ "$de" = kde ] && [ "$(readlink /etc/systemd/system/display-manager.service)" = /usr/lib/systemd/system/sddm.service ]; then
    sudo systemctl disable sddm.service
    sudo systemctl enable "$dm"
    echo "  login screen: SDDM -> Plasma Login Manager (after reboot)"
fi
systemctl --user enable --now podman.socket

# Bitwarden starts at login (to the tray), so its SSH agent is always there.
mkdir -p "$HOME/.config/autostart"
for f in /usr/share/applications/bitwarden*.desktop; do
    if [ -f "$f" ] && [ ! -e "$HOME/.config/autostart/${f##*/}" ]; then
        cp "$f" "$HOME/.config/autostart/"
    fi
done

say "firewall (deny incoming; allow KDE Connect / GSConnect)"
sudo ufw default deny incoming >/dev/null
sudo ufw default allow outgoing >/dev/null
sudo ufw allow 1714:1764/tcp >/dev/null
sudo ufw allow 1714:1764/udp >/dev/null
sudo ufw allow 51413 comment qBittorrent >/dev/null   # torrents: port set in qBittorrent.conf
sudo ufw --force enable >/dev/null
sudo systemctl enable ufw.service

say "desktop settings: $de"
if [ "$de" = kde ]; then
    # KWallet stores app secrets (gh token, Chromium, Wi-Fi); passwords are in Bitwarden.
    kwriteconfig6 --file kwalletrc --group Wallet --key Enabled true
    # no splash animation after login: straight to the desktop
    kwriteconfig6 --file ksplashrc --group KSplash --key Engine none
    kwriteconfig6 --file ksplashrc --group KSplash --key Theme None
    kwriteconfig6 --file kdeglobals --group General --key TerminalApplication ghostty
    kwriteconfig6 --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop
    kwriteconfig6 --file kglobalshortcutsrc --group services --group com.mitchellh.ghostty.desktop \
        --key _launch "Meta+Return"

    # Look: Breeze Dark colors, Darkly app style and window borders, Inter, Papirus-Dark, Bibata.
    kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop
    kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Darkly
    kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0.5
    kwriteconfig6 --file kdeglobals --group KDE --key ShowIconsInMenuItems false
    kwriteconfig6 --file kdeglobals --group KDE --key ShowIconsOnPushButtons false
    kwriteconfig6 --file kdeglobals --group KDE --key contrast 4
    kwriteconfig6 --file kdeglobals --group KDE --key frameContrast 0.2
    ui="Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key font "$ui"
    kwriteconfig6 --file kdeglobals --group General --key menuFont "$ui"
    kwriteconfig6 --file kdeglobals --group General --key toolBarFont "$ui"
    kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key fixed "JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group WM --key activeFont "Inter,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key XftAntialias true
    kwriteconfig6 --file kdeglobals --group General --key XftHintStyle hintslight
    kwriteconfig6 --file kdeglobals --group General --key XftSubPixel rgb
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.darkly
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Darkly
    kwriteconfig6 --file darklyrc --group Common --key ShadowStrength 51
    kwriteconfig6 --file darklyrc --group Windeco --key TitleAlignment AlignCenter
    kwriteconfig6 --file darklyrc --group Style --key MenuOpacity 85
    kwriteconfig6 --file darklyrc --group Style --key DolphinSidebarOpacity 85
    # These need a running Plasma session.
    if pgrep -x plasmashell >/dev/null; then
        plasma-apply-colorscheme BreezeDark
        plasma-apply-desktoptheme breeze-dark
        plasma-apply-cursortheme Bibata-Modern-Ice
        /usr/lib/plasma-changeicons Papirus-Dark
    else
        echo "!! not inside a Plasma session: log in once, then re-run '$0 kde' to finish the theme"
    fi
elif [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    echo "!! not inside a GNOME session: log in once, then re-run '$0 gnome' to apply settings"
else
    gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3
    kb=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty/
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$kb']"
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$kb" name Terminal
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$kb" command ghostty
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$kb" binding '<Super>Return'
fi

say "shell"
[ "$(getent passwd "$USER" | cut -d: -f7)" = /usr/bin/zsh ] || chsh -s /usr/bin/zsh

if [ -f "$dir/$host.sh" ]; then
    say "machine: $host"
    # shellcheck source=/dev/null
    . "$dir/$host.sh"
else
    say "no $host.sh: skipping machine-specific setup"
fi

if [ "$rebuild" = 1 ]; then
    say "rebuilding boot image (kernel options changed)"
    sudo mkinitcpio -P
fi

say "done: reboot now"
echo "After reboot: set the battery limit in System Settings > Power (KDE),"
echo "and see ~/.github/README.md for the per-machine checks."
