#!/bin/sh
# Set up this machine after a minimal archinstall.
#   ~/.setup/install.sh niri      or      ~/.setup/install.sh gnome
# (KDE Plasma: the `kde` branch of the dotfiles repo.)
# Safe to re-run: every step skips what is already done.
set -eu

de=${1:-}
case $de in
    gnome) dm=gdm.service ;;
    # niri: greetd + Noctalia's greeter (set up below, under "services").
    niri) dm=greetd.service ;;
    *) echo "usage: $0 niri|gnome" >&2; exit 1 ;;
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
theme="org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark"
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

say "systemd-oomd (kill the app using too much memory before the system freezes)"
# Fedora's defaults (package systemd-oomd-defaults): kill under sustained memory
# pressure in user sessions, or when swap (zram) is nearly full. It kills one
# cgroup: an app started from niri or Noctalia, not the whole session.
sudo mkdir -p /etc/systemd/system/user@.service.d /etc/systemd/system/-.slice.d
printf '[Service]\nManagedOOMMemoryPressure=kill\nManagedOOMMemoryPressureLimit=50%%\n' |
    sudo tee /etc/systemd/system/user@.service.d/10-oomd.conf >/dev/null
printf '[Slice]\nManagedOOMSwap=kill\n' | sudo tee /etc/systemd/system/-.slice.d/10-oomd.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now systemd-oomd.service

say "SSD TRIM"
root=$(findmnt -no SOURCE /)
luks_discard "${root#/dev/mapper/}"

say "services"
sudo systemctl enable --now bluetooth.service cups.socket fstrim.timer paccache.timer reflector.timer

# niri's login screen: greetd runs Noctalia's greeter (noctalia-greeter docs,
# "Installation"). Arch's greetd PAM file has no gnome-keyring line, so it is
# added: the login password then unlocks the keyring.
if [ "$de" = niri ]; then
    cmd=/usr/bin/noctalia-greeter-session
    if ! grep -q "^command = \"$cmd\"" /etc/greetd/config.toml 2>/dev/null; then
        [ -f /etc/greetd/config.toml.orig ] || sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.orig
        sudo tee /etc/greetd/config.toml >/dev/null <<EOF
# Written by ~/.setup/install.sh niri (original: config.toml.orig).
[terminal]
vt = 1

[default_session]
command = "$cmd"
user = "greeter"
EOF
    fi
    pam=/etc/pam.d/greetd
    grep -q '^auth.*pam_gnome_keyring' "$pam" ||
        printf 'auth       optional     pam_gnome_keyring.so\n' | sudo tee -a "$pam" >/dev/null
    grep -q '^session.*pam_gnome_keyring' "$pam" ||
        printf 'session    optional     pam_gnome_keyring.so auto_start\n' | sudo tee -a "$pam" >/dev/null
    grep -q '^password.*pam_gnome_keyring' "$pam" ||
        printf 'password   optional     pam_gnome_keyring.so\n' | sudo tee -a "$pam" >/dev/null
    sudo systemd-tmpfiles --create noctalia-greeter.conf
    sudo noctalia-greeter-apply-appearance --setup-system
fi

# Keep a login screen that is already set up; only enable one on a fresh install.
# niri replaces any other one with greetd. Both switches apply at the next boot.
current=$(readlink /etc/systemd/system/display-manager.service 2>/dev/null || true)
if [ -z "$current" ]; then
    sudo systemctl enable "$dm"
elif [ "$de" = niri ] && [ "${current##*/}" != "$dm" ]; then
    sudo systemctl disable "${current##*/}"
    sudo systemctl enable "$dm"
    echo "  login screen: ${current##*/} -> $dm (after reboot)"
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
if [ "$de" = niri ]; then
    # Config is in the dotfiles (~/.config/niri, ~/.config/noctalia); this links
    # this machine's screen/GPU file and turns on the session services.
    if [ -f "$HOME/.config/niri/hosts/$host.kdl" ]; then
        ln -sfn "hosts/$host.kdl" "$HOME/.config/niri/host.kdl"
        echo "  niri: host.kdl -> hosts/$host.kdl"
    else
        echo "!! no ~/.config/niri/hosts/$host.kdl: niri uses its screen defaults"
    fi
    niri validate
    noctalia config validate
    mkdir -p "$HOME/Pictures/Screenshots"

    # Wallpapers: a nature default per mode, from Wallhaven. If a download
    # fails, Noctalia shows its own wallpaper; nothing else depends on these.
    #   Dark:  5y3q31, Milky Way over a mountain lake (Unsplash photo)
    #   Light: e89l8k, clouds on a blue sky
    get_wallpaper() {
        [ -s "$2" ] && return 0
        mkdir -p "${2%/*}"
        curl -fsSL -o "$2.part" "$1" && mv "$2.part" "$2" || echo "!! could not download $1"
    }
    w="$HOME/Pictures/Wallpapers"
    get_wallpaper https://w.wallhaven.cc/full/5y/wallhaven-5y3q31.jpg "$w/Dark/wallhaven-5y3q31.jpg"
    get_wallpaper https://w.wallhaven.cc/full/e8/wallhaven-e89l8k.jpg "$w/Light/wallhaven-e89l8k.jpg"
    # Defaults for ~/.local/bin/wallpaper-mode; your later picks replace them.
    state="$HOME/.local/state/wallpaper-mode"
    mkdir -p "$state"
    [ -s "$state/dark" ] || echo "$w/Dark/wallhaven-5y3q31.jpg" >"$state/dark"
    [ -s "$state/light" ] || echo "$w/Light/wallhaven-e89l8k.jpg" >"$state/light"

    # Noctalia runs as a user service started with niri (not in other desktops).
    systemctl --user daemon-reload
    systemctl --user enable noctalia.service

    # GTK look; Noctalia adds the wallpaper colors on top (gtk.css import).
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark
        gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark
        gsettings set org.gnome.desktop.interface cursor-theme Adwaita
        gsettings set org.gnome.desktop.interface cursor-size 24
        gsettings set org.gnome.desktop.interface font-name "Inter 10"
        gsettings set org.gnome.desktop.interface monospace-font-name "JetBrainsMono Nerd Font 10"
    else
        echo "!! no desktop session: log in once, then re-run '$0 niri' for the GTK settings"
    fi

    # Qt look (qt6ct): Noctalia writes colors/noctalia.conf on every wallpaper
    # change. Only a starting config; qt6ct's own window edits it afterwards.
    if [ ! -e "$HOME/.config/qt6ct/qt6ct.conf" ]; then
        mkdir -p "$HOME/.config/qt6ct"
        cat > "$HOME/.config/qt6ct/qt6ct.conf" <<EOF
[Appearance]
color_scheme_path=$HOME/.config/qt6ct/colors/noctalia.conf
custom_palette=true
icon_theme=Papirus-Dark
style=Fusion

[Fonts]
fixed="JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
general="Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
EOF
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

# Battery charge limit, through UPower: works in every desktop and is switched
# with `charge-limit on|off|toggle` (the bar button in Noctalia). The machine's
# script may set charge_limit; 90 otherwise. Charging restarts 5% below it
# (only on batteries that support a start point, like the T14's).
charge_limit=${charge_limit:-90}
if ls /sys/class/power_supply/*/charge_control_end_threshold >/dev/null 2>&1; then
    say "battery: stop charging at $charge_limit%"
    hwdb=/etc/udev/hwdb.d/61-battery-local.hwdb
    want=$(printf '# Written by ~/.setup/install.sh: UPower charge limit (start,end).\nbattery:*:*:dmi:*\n CHARGE_LIMIT=%s,%s\n' \
        "$((charge_limit - 5))" "$charge_limit")
    if [ "$(cat "$hwdb" 2>/dev/null)" != "$want" ]; then
        printf '%s\n' "$want" | sudo tee "$hwdb" >/dev/null
        sudo systemd-hwdb update
        sudo udevadm trigger --subsystem-match=power_supply
        sudo udevadm settle
        sudo systemctl restart upower.service
        sleep 2
        # New or changed limit: turn it on. A later `charge-limit off` is kept.
        "$HOME/.local/bin/charge-limit" on
    fi
fi

if [ "$rebuild" = 1 ]; then
    say "rebuilding boot image (kernel options changed)"
    sudo mkinitcpio -P
fi

say "done: reboot now"
echo "Battery limit: charge-limit (on|off|toggle). See ~/.github/README.md for"
echo "the per-machine checks."
