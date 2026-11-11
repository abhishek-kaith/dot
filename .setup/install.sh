#!/bin/sh
# Set up this machine after a minimal archinstall: install.sh niri|gnome
# (KDE: the `kde` branch). Safe to re-run.
set -eu

de=${1:-}
case $de in
    gnome) dm=gdm.service ;;
    niri) dm=greetd.service ;;
    *) echo "usage: $0 niri|gnome" >&2; exit 1 ;;
esac

dir=$(cd "$(dirname "$0")" && pwd)
host=$(cat /etc/hostname)
rebuild=0

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
list() { sed 's/#.*//' "$@" | tr -s ' \t' '\n' | grep -v '^$'; }

# Append a kernel option to /etc/kernel/cmdline (unified kernel image; rebuilt
# once at the end). Skips duplicates; keeps cmdline.orig.
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

# TRIM through LUKS2, stored in the header.
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

# AUR (read each PKGBUILD before adding one); yay-bin is built once with makepkg.
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

# qBittorrent starting config (port 51413); never overwrites.
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
# Fedora's defaults: kill the app under memory pressure or with zram nearly full.
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

# niri's login screen: greetd + Noctalia's greeter, keyring unlock in its PAM.
if [ "$de" = niri ]; then
    # Autologin once per boot (the keyring then asks once). Off: autologin=no
    cmd=/usr/bin/noctalia-greeter-session
    want="# Written by ~/.setup/install.sh niri (original: config.toml.orig).
[terminal]
vt = 1

[default_session]
command = \"$cmd\"
user = \"greeter\""
    if [ "${autologin:-yes}" = yes ]; then
        want="$want

[initial_session]
command = \"niri-session\"
user = \"$USER\""
    fi
    if [ "$(cat /etc/greetd/config.toml 2>/dev/null)" != "$want" ]; then
        [ -f /etc/greetd/config.toml.orig ] || sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.orig
        printf '%s\n' "$want" | sudo tee /etc/greetd/config.toml >/dev/null
        echo "  greetd: autologin ${autologin:-yes}"
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
    # Let Noctalia sync its look to the login screen without a password prompt
    # (a narrow polkit rule for that one helper; the greeter's own command).
    sudo noctalia-greeter passwordless-sync enable "$USER"
fi

# Enable the login screen on a fresh install; niri swaps any other for greetd.
current=$(readlink /etc/systemd/system/display-manager.service 2>/dev/null || true)
if [ -z "$current" ]; then
    sudo systemctl enable "$dm"
elif [ "$de" = niri ] && [ "${current##*/}" != "$dm" ]; then
    sudo systemctl disable "${current##*/}"
    sudo systemctl enable "$dm"
    echo "  login screen: ${current##*/} -> $dm (after reboot)"
fi
systemctl --user enable --now podman.socket

# Bitwarden at login, for its SSH agent.
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
    if [ -f "$HOME/.config/niri/hosts/$host.kdl" ]; then
        ln -sfn "hosts/$host.kdl" "$HOME/.config/niri/host.kdl"
        echo "  niri: host.kdl -> hosts/$host.kdl"
    else
        echo "!! no ~/.config/niri/hosts/$host.kdl: niri uses its screen defaults"
    fi
    niri validate
    noctalia config validate
    mkdir -p "$HOME/Pictures/Screenshots"

    # Default wallpaper per mode, from Wallhaven (on failure: Noctalia's own).
    get_wallpaper() {
        [ -s "$2" ] && return 0
        mkdir -p "${2%/*}"
        curl -fsSL -o "$2.part" "$1" && mv "$2.part" "$2" || echo "!! could not download $1"
    }
    w="$HOME/Pictures/Wallpapers"
    get_wallpaper https://w.wallhaven.cc/full/5y/wallhaven-5y3q31.jpg "$w/Dark/wallhaven-5y3q31.jpg"
    get_wallpaper https://w.wallhaven.cc/full/e8/wallhaven-e89l8k.jpg "$w/Light/wallhaven-e89l8k.jpg"
    # wallpaper-mode's defaults; your picks replace them.
    state="$HOME/.local/state/wallpaper-mode"
    mkdir -p "$state"
    [ -s "$state/dark" ] || echo "$w/Dark/wallhaven-5y3q31.jpg" >"$state/dark"
    [ -s "$state/light" ] || echo "$w/Light/wallhaven-e89l8k.jpg" >"$state/light"

    systemctl --user daemon-reload
    systemctl --user enable noctalia.service

    # GTK look (Noctalia adds the wallpaper colors).
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

    # Default apps.
    xdg-mime default org.gnome.Nautilus.desktop inode/directory
    xdg-mime default org.gnome.Papers.desktop application/pdf
    xdg-mime default org.gnome.Loupe.desktop image/png image/jpeg image/webp \
        image/gif image/avif image/jxl image/heic image/bmp image/tiff image/svg+xml
    xdg-mime default org.gnome.TextEditor.desktop text/plain text/markdown
    xdg-mime default org.gnome.Showtime.desktop video/mp4 video/x-matroska video/webm \
        video/quicktime video/x-msvideo
    xdg-mime default org.gnome.Decibels.desktop audio/mpeg audio/flac audio/ogg \
        audio/x-wav audio/mp4 audio/opus

    # Qt look (qt6ct); starting config only.
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

# Battery charge limit (UPower; toggled in Noctalia's Power tab). A machine
# script may set charge_limit (default 90); charging restarts 5% below.
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
        # Only when the limit changes, so turning it off later sticks.
        for dev in $(upower -e | grep '/battery_BAT'); do
            busctl --system call org.freedesktop.UPower "$dev" \
                org.freedesktop.UPower.Device EnableChargeThreshold b true || true
        done
    fi
fi

if [ "$rebuild" = 1 ]; then
    say "rebuilding boot image (kernel options changed)"
    sudo mkinitcpio -P
fi

say "done: reboot now"
echo "Battery limit: control center > Power. See ~/.github/README.md for"
echo "the per-machine checks."
