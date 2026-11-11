# dot

My Arch Linux setup: dotfiles in a **bare git repo** (`$HOME` is the work tree) and one POSIX `sh` script that turns a minimal Arch install into a working laptop with **niri** + **Noctalia** (or GNOME). The old KDE Plasma setup is on the [`kde` branch](https://github.com/abhishek-kaith/dot/tree/kde).

| Hostname | Laptop |
|---|---|
| `tuf-a15` | ASUS TUF Gaming A15 (FA506NCG): Ryzen 7 7445HS + Radeon 740M, RTX 3050 (hybrid) |
| `t14-amd` | Lenovo ThinkPad T14 Gen 1 AMD |

- [Install](#install) · [What gets installed](#what-gets-installed) · [Passwords, 2FA, SSH](#passwords-2fa-ssh) · [Daily use](#daily-use)
- [niri + Noctalia](#niri--noctalia) · [Keys](#keys) · [Layout](#layout)
- [Per-machine notes](#per-machine-notes) · [Kernel options](#kernel-options) · [Troubleshooting](#troubleshooting)

---

## Install

**1. archinstall:** profile **Minimal**, kernel `linux` (or `linux-zen`), systemd-boot (unified kernel image), LUKS, PipeWire, NetworkManager, zram, hostname `tuf-a15` or `t14-amd` (it picks the machine script).

**2. Bootstrap** from the console (Wi-Fi: `nmtui`):

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/abhishek-kaith/dot/main/.setup/bootstrap.sh)" -- niri   # or -- gnome
```

It clones the repo into `~/.dotfiles`, checks it out into `$HOME` (files in the way go to `~/.dotfiles-backup/`) and runs `~/.setup/install.sh`. Re-running `install.sh` is safe; it skips what's done (but resets default apps and the GTK look to the repo's).

**3. Reboot, then once per machine:**

```sh
gh auth login
git config --file ~/.config/git/local user.name  "Your Name"
git config --file ~/.config/git/local user.email "you@example.com"
bw login && export BW_SESSION=$(bw unlock --raw) && ssh-config-sync pull && bw lock
```

- **Bitwarden:** log in; Settings > *Enable SSH agent*, *Start to tray*, *Close to tray*; install its extension in Zen and Chromium.
- **Ente Auth:** log in (or offline), turn on App lock.
- **Mic:** default input *Noise Canceling Source*.
- **niri:** fill `~/.config/niri/hosts/<hostname>.kdl` from `niri msg outputs` (panel, refresh rate, VRR).
- **GNOME only:** GSConnect from Extension Manager, then re-run `~/.setup/install.sh gnome` from inside GNOME.

---

## What gets installed

Plain lists in `~/.setup/`: [`common.txt`](../.setup/common.txt) (shell, CLI, apps, drivers, fonts), [`niri.txt`](../.setup/niri.txt), [`gnome.txt`](../.setup/gnome.txt), [`flatpak.txt`](../.setup/flatpak.txt). Edit, re-run `install.sh`. Rule: **pacman** for the system, **mise** for runtimes and dev tools, **Flatpak** for GUI apps pacman lacks.

**Apps:** Ghostty, Zen (Flatpak) + Chromium, Bitwarden, Ente Auth (Flatpak), LibreOffice, Telegram, OBS, Shotwell + Pinta, scrcpy, qBittorrent, and GNOME's Nautilus, Loupe, Papers, Text Editor, Showtime/Celluloid, Amberol/Decibels, Snapshot. Phone: KDE Connect (niri) / GSConnect (GNOME).

**CLI:** zsh + starship, tmux, neovim, mise, git + delta + lazygit, gh, ripgrep, fd, fzf, zoxide, bat, eza, dust, btop, jq, yq, xh, tealdeer, powertop; network: dig, doggo, mtr, gping, nmap, nc, iperf3, tcpdump, bandwhich, wg.

**System setup by `install.sh`:**
- systemd-oomd (Fedora's defaults: kills the one app eating memory before the system freezes); zram tuned per the Arch wiki; TRIM through LUKS2.
- Battery stops charging at 90% (UPower; `charge_limit=` in a machine script changes it).
- Services: bluetooth, cups, fstrim/paccache/reflector timers, `podman.socket` (user).
- ufw: deny incoming; open 1714–1764 (KDE Connect) and 51413 (qBittorrent, whose starting config is [`qBittorrent.conf`](../.setup/qBittorrent.conf)).
- Bitwarden in autostart (its SSH agent), zsh as login shell, then `~/.setup/<hostname>.sh`.
- niri: greetd + Noctalia's greeter with **autologin**, keyring unlock in its PAM file, passwordless login-screen sync, `noctalia.service`, GTK/Qt look, default apps, wallpapers.

**Containers:** rootless Podman; `podman-docker` + `podman.socket` + `DOCKER_HOST` make `docker`, `docker-compose`, lazydocker and testcontainers work unchanged.

**Dev tools:** global ones in [`~/.config/mise/config.toml`](../.config/mise/config.toml); projects pin theirs in `mise.toml`. Python through `uv`. `environment.d` points browser tooling (Puppeteer, Lighthouse, Playwright MCP) at the system Chromium; Playwright's test runner keeps its own (`npx playwright install chromium`).

---

## Passwords, 2FA, SSH

| What | Where |
|---|---|
| Passwords, notes, recovery codes | **Bitwarden** |
| 2FA codes, including Bitwarden's own | **Ente Auth**, kept apart from the passwords |
| App secrets (`gh` token, Chromium's key, Wi-Fi) | **gnome-keyring** |

**SSH keys live in Bitwarden**; its agent socket is `SSH_AUTH_SOCK` (`~/.config/environment.d/10-env.conf`), so no key files. Bitwarden must be running and unlocked; each use asks for approval. `~/.ssh/config` stays out of this public repo, in a Bitwarden note: `ssh-config-sync push|pull`. Hosts pin a key with `IdentityFile ~/.ssh/keys/<name>.pub` + `IdentitiesOnly yes`; GitHub accounts get aliases (`git clone git@github-zti:org/repo.git`).

---

## Daily use

```sh
dot status / dot add <file> / dot commit / dot push    # dot = git on the bare repo; lazydot = lazygit
yay && mise up && flatpak update && fwupdmgr update      # system + AUR, dev tools, Flatpaks, firmware
powerprofilesctl set performance                       # on AC for heavy work; sudo powertop for real draw
```

Only `dot add`ed files are tracked (`status.showUntrackedFiles no`).

---

## niri + Noctalia

[niri](https://github.com/YaLTeR/niri) 26.04 scrolls windows in columns; [Noctalia](https://docs.noctalia.dev/noctalia/) 5.4.1 is the shell (bar, launcher, notifications, lock, idle, polkit, wallpaper). Both from Arch's repos. Noctalia's website documents its development version: check new options with `noctalia config validate`, niri ones with `niri validate`.

| File | Tracked | What |
|---|---|---|
| `~/.config/niri/config.kdl` | ✓ | input, layout, rules, keys |
| `~/.config/niri/hosts/<hostname>.kdl` | ✓ | screens, refresh rate, VRR, GPU; linked as `host.kdl` by `install.sh` |
| `~/.config/noctalia/config.toml` | ✓ | bar, theme, idle, night light |
| `~/.local/state/noctalia/settings.toml` | | Noctalia's Settings window writes here and wins over `config.toml`; copy keepers back |
| `noctalia.kdl`, `ghostty/noctalia-colors`, `gtk-*/noctalia.css`, `qt6ct/colors/` | | wallpaper colors, rewritten by Noctalia |

- **Look:** thin blurred bar on top; colors follow the wallpaper (Noctalia, niri borders, GTK, Qt, Ghostty, btop). Dark/light also swaps the wallpaper: each mode has a folder, `~/Pictures/Wallpapers/{Dark,Light}`, and remembers its last pick (`wallpaper-mode`, a Noctalia hook). Defaults come from Wallhaven ([dark](https://wallhaven.cc/w/5y3q31), [light](https://wallhaven.cc/w/e89l8k)). No Noctalia plugins.
- **Control center** (`Mod+S`): Dark Mode, Night Light (left-click: scheduled 19:30–07:00; right-click: always on), Caffeine (never sleep), power profile, Do Not Disturb, mic; Power tab: battery limit on/off.
- **Idle:** lock at 10 min, screen off at 11, suspend at 30 on battery only. Caffeine and playing video hold them off.
- **Login:** autologin into niri (the disk password is the gate); the keyring then asks for your password once. The greeter (after logout) follows Noctalia's look; avatar `~/.face`. Turn autologin off: `autologin=no ~/.setup/install.sh niri`.
- **Privacy:** Bitwarden, Ente Auth and KeePassXC are black in screen sharing; so are notifications.
- **File dialogs** come from the GTK portal ([`niri-portals.conf`](../.config/xdg-desktop-portal/niri-portals.conf)); GNOME's starts Nautilus first and is slow.
- **Memory:** apps started from Noctalia or niri each get their own cgroup, so systemd-oomd kills only the culprit.

### Keys

Mod is Super. System actions use macOS keys where niri leaves them free; windows use the i3/Hyprland layout (Shift moves, Ctrl = workspaces, Alt = monitors, arrows = H/J/K/L). `Mod+Shift+/` lists everything.

| Key | Does |
|---|---|
| `Mod+Space` (`Mod+D`) · `Mod+Ctrl+Space` | search · emoji |
| `Mod+S` · `Mod+N` · `Mod+V` · `Mod+Shift+,` | control center · notifications · clipboard · settings |
| `Mod+P` / `Print` · `Ctrl+Print` | screenshot (pick) · whole screen |
| `Mod+Ctrl+Q` · `Mod+Shift+E` | lock · power menu |
| `Mod+Shift+W` · `Mod+Shift+D` · `Mod+Shift+N` | wallpaper · dark/light · Do Not Disturb |
| `Mod+Return` (`Mod+T`) · `Mod+B` · `Mod+E` | Ghostty · Zen · Files |
| `Mod+Q` / `Alt+F4` · `Mod+O` · `Alt+Tab` | close · overview · recent windows |
| `Mod+H/J/K/L` · `+Shift` | focus · move (J/K run on into the next workspace) |
| `Mod+Ctrl+J/K` · `+Shift` · `Mod+1–9` · `Mod+Shift+1–9` | workspace down/up · take the column · go to · send to |
| `Mod+Alt+H/J/K/L` · `+Shift` | focus monitor · send column |
| `Mod+F` · `Mod+Shift+F` · `Mod+M` · `Mod+R` · `Mod+-/=` | full width · fullscreen · fill screen · cycle widths · narrower/wider |
| `Mod+,` / `Mod+.` · `Mod+[` / `Mod+]` · `Mod+W` · `Mod+C` | merge into / split out of the column · into/out of the neighbour · tabs on/off · center |
| `Mod+Shift+Space` · `Mod+Alt+Space` | float/tile · focus floating/tiled |

---

## Layout

```
~/.setup/                       bootstrap.sh, install.sh niri|gnome, package lists, <hostname>.sh
~/.zshenv, ~/.config/zsh/       zsh (.zshenv only sets paths: non-interactive shells read it)
~/.config/environment.d/        session env for everything the desktop starts (SSH_AUTH_SOCK, PATH)
~/.config/niri/, noctalia/      desktop (see above); systemd/user/: noctalia.service + niri env
~/.config/ghostty/, tmux/, nvim/, git/, mise/, starship.toml, tealdeer/, pipewire/ (mic denoise), containers/
~/.local/bin/                   gpu-mode, wallpaper-mode, ssh-config-sync, tmux-sessionizer
```

---

## Per-machine notes

### `tuf-a15`

Panel and USB-C run on the AMD GPU; **HDMI is wired to the NVIDIA one**. [`tuf-a15.sh`](../.setup/tuf-a15.sh) installs `nvidia-open` + `nvidia-prime` + `nvtop`, removes `libva-nvidia-driver` (it kept the GPU awake), adds `acpi_backlight=native` (brightness), enables `nvidia-powerd` (Dynamic Boost on AC) and installs `gpu-mode-boot.service`. niri renders on AMD (`render-drm-device` in `hosts/tuf-a15.kdl`).

**The NVIDIA GPU never sleeps in hybrid** (firmware NVPCF bug, [open-gpu-kernel-modules #1300](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1300)): ~17 W idle instead of ~8. So use the firmware's switch:

```sh
gpu-mode            # eco or hybrid
gpu-mode eco        # NVIDIA off: best battery; no CUDA, prime-run or HDMI
gpu-mode hybrid     # NVIDIA on at once: CUDA, prime-run, HDMI
```

In hybrid niri holds the GPU for HDMI, so `eco` is then scheduled for the next boot (before the login screen); `gpu-mode hybrid` cancels it. `gpu-mode hdmi off` makes niri never open the GPU (no HDMI, eco always instant); `hdmi auto` undoes it. Games: `prime-run %command%`; CUDA finds the GPU itself. A CUDA process keeps the GPU awake (`nvtop`). On battery use USB-C for external screens, and `niri msg output eDP-1 mode 1920x1080@60` saves a bit more.

### `t14-amd`

**BIOS:** Sleep State = **Linux**; **never enroll your own Secure Boot keys** (bricks it); `fwupdmgr update`. [`t14-amd.sh`](../.setup/t14-amd.sh): `fprintd`, `alsa-utils` (mic LED), `mem_sleep_default=deep`, warns if not `amd-pstate`. Charge limit 85–90%. If needed: Wi-Fi drops → `options iwlwifi 11n_disable=8`; dead click after resume → `psmouse.synaptics_intertouch=0`.

**`/data` drive** (second LUKS disk, keyfile unlock):

```sh
sudo dd if=/dev/urandom of=/etc/cryptsetup-keys.d/data.key bs=512 count=4 && sudo chmod 600 /etc/cryptsetup-keys.d/data.key
sudo cryptsetup luksAddKey /dev/disk/by-uuid/<UUID> /etc/cryptsetup-keys.d/data.key     # <UUID>: lsblk -f
echo 'data UUID=<UUID> /etc/cryptsetup-keys.d/data.key discard' | sudo tee -a /etc/crypttab
echo '/dev/mapper/data /data ext4 noatime,nofail 0 2' | sudo tee -a /etc/fstab
```

**From KDE to niri:** the scripts are on the `kde` branch. Save one with `dot show kde:.setup/remove-kde.sh > /tmp/remove-kde.sh`. Order: `kwallet-to-keyring.py` from Plasma (copies KWallet secrets to gnome-keyring), `install.sh niri`, reboot, `remove-kde.sh` from niri.

### New machine

Pick a hostname; add `~/.setup/<hostname>.sh` and `~/.config/niri/hosts/<hostname>.kdl`; add a row at the top.

### Kernel options

`kernel_param <option>` appends to `/etc/kernel/cmdline` (unified kernel image), skips duplicates, keeps `cmdline.orig`, and rebuilds once at the end. Check: `cat /proc/cmdline`. Undo: edit the file, `sudo mkinitcpio -P`. Unbootable: `e` in the systemd-boot menu, or chroot from the Arch USB. In use: `acpi_backlight=native` (tuf-a15), `mem_sleep_default=deep` (t14-amd).

---

## Troubleshooting

| Problem | Check |
|---|---|
| ssh: no agent | Bitwarden running, unlocked, SSH agent on; `echo $SSH_AUTH_SOCK` |
| `gh` token invalid | `secret-tool search service gh:github.com` (keyring unlocked?), `gh auth login` |
| Bar missing | `systemctl --user status noctalia`; `journalctl --user -u noctalia -b` |
| Config error banner | `niri validate`; `noctalia config validate` |
| Login screen doesn't start | `Ctrl+Alt+F2`, `systemctl status greetd`; `niri-session` from the console |
| NVIDIA awake | `gpu-mode eco`; `sudo fuser -v /dev/nvidia*`; `libva-nvidia-driver` back? |
| Brightness dead | `ls /sys/class/backlight/` shows `amdgpu_bl*`? |
| docker can't connect | `systemctl --user status podman.socket`; `echo $DOCKER_HOST` |
| Broken update | live USB, `arch-chroot`, `pacman -U /var/cache/pacman/pkg/<old>` |
