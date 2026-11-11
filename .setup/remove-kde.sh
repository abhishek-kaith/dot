#!/bin/sh
# Remove KDE Plasma and the KDE apps from this machine, after moving to niri.
#   ~/.setup/remove-kde.sh         dry run: show what would go
#   ~/.setup/remove-kde.sh --yes   do it (pacman still asks before removing)
#
# Run it from niri, not Plasma, once niri's login screen (greetd) is enabled:
# Plasma Login Manager is part of Plasma, so it goes too.
#
# Kept: kdeconnect (phone link, works without Plasma), Inter, Papirus and your
# KDE Connect pairing (~/.config/kdeconnect). The KDE setup itself lives on in
# the dotfiles' `kde` branch.
# KDE settings in $HOME are moved, not deleted, to ~/.kde-backup-<date>
# (including the KWallet file, a backup of the secrets now in gnome-keyring).
set -eu

yes=0
[ "${1:-}" = --yes ] && yes=1
say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

case "${XDG_CURRENT_DESKTOP:-}" in
    *KDE*) echo "!! this is a Plasma session: log into niri first" >&2; exit 1 ;;
esac
if pgrep -x plasmashell >/dev/null; then
    echo "!! Plasma is running: log out of it and run this from niri" >&2
    exit 1
fi
dm=$(readlink /etc/systemd/system/display-manager.service 2>/dev/null || true)
if [ "${dm##*/}" != greetd.service ]; then
    echo "!! the login screen is '${dm##*/}', not greetd: run ~/.setup/install.sh niri first" >&2
    exit 1
fi

# What the KDE install put there (kde.txt + kde-aur.txt on the `kde` branch),
# minus kdeconnect, inter-font and papirus-icon-theme, which niri keeps.
keep="kdeconnect inter-font papirus-icon-theme"
pkgs=
for p in plasma-meta dolphin ark filelight partitionmanager okular gwenview kcalc kate \
    ffmpegthumbs kdegraphics-thumbnailers haruna elisa kamoso \
    darkly-bin bibata-cursor-theme-bin kwin-karousel kwin-effects-geometry-change; do
    pacman -Qq "$p" >/dev/null 2>&1 && pkgs="$pkgs $p"
done

say "packages (with dependencies nothing else needs)"
if [ -n "$pkgs" ]; then
    # shellcheck disable=SC2086
    pacman -Rs --print --print-format '%n' $pkgs | sort | tr '\n' ' ' | fold -s -w 100
    echo
    # shellcheck disable=SC2086
    echo "$(pacman -Rs --print $pkgs | wc -l) packages"
    for p in $keep; do
        # shellcheck disable=SC2086
        if pacman -Rs --print --print-format '%n' $pkgs | grep -qx "$p"; then
            echo "!! $p would be removed: stopping" >&2
            exit 1
        fi
    done
else
    echo "none installed"
fi

# Settings files KDE apps leave in $HOME. kdeconnect is kept on purpose.
stamp=$(date +%Y%m%d)
backup="$HOME/.kde-backup-$stamp"
files=
for f in \
    .config/baloofilerc .config/bluedevilglobalrc .config/darklyrc .config/discoverrc \
    .config/dolphinrc .config/elisarc .config/gwenviewrc .config/haruna .config/kaccessrc \
    .config/kactivitymanagerdrc .config/kactivitymanagerd-statsrc .config/kate \
    .config/kate-externaltoolspluginrc .config/katerc .config/katevirc .config/kcminputrc \
    .config/kconf_updaterc .config/KDE .config/kded5rc .config/kded6rc .config/kdedefaults \
    .config/kdeglobals .config/kde.org .config/kglobalshortcutsrc .config/kiorc .config/klassy \
    .config/ksmserverrc .config/ksplashrc .config/ktimezonedrc .config/kwalletrc \
    .config/kwinoutputconfig.json .config/kwinrc .config/kwinrulesrc .config/okularpartrc \
    .config/okularrc .config/plasma-localerc .config/plasmanotifyrc \
    .config/plasma-org.kde.plasma.desktop-appletsrc .config/plasmaparc .config/plasmarc \
    .config/plasmashellrc .config/plasma-welcomerc .config/plasma-workspace .config/powerdevilrc \
    .config/powermanagementprofilesrc .config/spectaclerc .config/systemsettingsrc \
    .config/trashrc .config/xsettingsd \
    .local/share/baloo .local/share/dolphin .local/share/elisa .local/share/gwenview \
    .local/share/haruna .local/share/kactivitymanagerd .local/share/kate .local/share/klipper \
    .local/share/knewstuff3 .local/share/kpeoplevcard .local/share/krunnerstaterc \
    .local/share/kwalletd .local/share/kwin .local/share/okular .local/share/plasmalogin \
    .local/share/plasma-systemmonitor .local/share/plasma; do
    [ -e "$HOME/$f" ] && files="$files $f"
done
say "KDE settings in \$HOME -> $backup"
echo "${files:-none}" | tr ' ' '\n' | grep -v '^$' || true

# System files that only KWin used (tuf-a15: GPU names for KWIN_DRM_DEVICES).
sysfiles=
[ -e /etc/udev/rules.d/61-gpu-names.rules ] && sysfiles="/etc/udev/rules.d/61-gpu-names.rules"
say "system files"
echo "${sysfiles:-none}"

if [ "$yes" = 0 ]; then
    printf '\ndry run: nothing changed. Run again with --yes.\n'
    exit 0
fi

if [ -n "$pkgs" ]; then
    say "removing packages"
    # shellcheck disable=SC2086
    sudo pacman -Rns $pkgs
fi
if [ -n "$files" ]; then
    say "moving settings to $backup"
    for f in $files; do
        mkdir -p "$backup/$(dirname "$f")"
        mv "$HOME/$f" "$backup/$f"
    done
fi
if [ -n "$sysfiles" ]; then
    sudo rm -f $sysfiles
    sudo udevadm control --reload
fi

say "left over: packages nothing needs any more (not removed; check first)"
pacman -Qdtq || echo "none"
say "done: reboot. Delete $backup once you're sure."
