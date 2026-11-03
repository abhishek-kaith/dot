# dot

My Arch Linux setup: dotfiles, kept in a **bare git repo** with `$HOME` as the work tree, and one POSIX `sh` script that turns a minimal Arch install into a working laptop for KDE Plasma or GNOME.

Machines:

| Hostname | Laptop | Notes |
|---|---|---|
| `tuf-a15` | ASUS TUF Gaming A15 (FA506NCG): Ryzen 7 7445HS + Radeon 740M, RTX 3050 Laptop | hybrid graphics |
| `t14-amd` | Lenovo ThinkPad T14 Gen 1 AMD (Ryzen 4000) | AMD only |

---

## Contents

- [Fresh install](#fresh-install)
- [What gets installed](#what-gets-installed) · [Containers](#containers-rootless-podman)
- [Daily use](#daily-use)
- [Layout](#layout)
- [Per-machine notes](#per-machine-notes) · [Kernel options](#kernel-options)
- [Theming: Qt, GTK, Flatpak, Electron, AppImage](#theming)
- [Troubleshooting](#troubleshooting)

---

## Fresh install

### 1. archinstall

Boot the Arch ISO and run `archinstall`:

| Setting | Choose |
|---|---|
| Profile | **Minimal** (the script installs the desktop and the right GPU drivers) |
| Kernel | `linux` |
| Bootloader | systemd-boot (unified kernel image) |
| Disk | LUKS encryption |
| Audio | PipeWire |
| Network | NetworkManager |
| Swap | zram |
| Hostname | `tuf-a15` or `t14-amd`: picks the machine script |

### 2. Bootstrap

Log in on the console, connect to Wi-Fi (`nmtui`), then:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/abhishek-kaith/dot/main/.setup/bootstrap.sh)" -- kde
```

(`-- gnome` for GNOME.) That clones this repo into `~/.dotfiles`, checks the files out into `$HOME` (anything in the way is moved to `~/.dotfiles-backup/`), and runs `~/.setup/install.sh`.

The same thing by hand:

```sh
git clone --bare https://github.com/abhishek-kaith/dot.git ~/.dotfiles
git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout
git --git-dir=$HOME/.dotfiles --work-tree=$HOME config status.showUntrackedFiles no
~/.setup/install.sh kde
```

### 3. Reboot, then once per machine

```sh
gh auth login                                   # GitHub; also sets up git credentials
git config --file ~/.config/git/local user.name  "Abhishek Kaith"
git config --file ~/.config/git/local user.email "you@example.com"
```

- **Battery limit:** System Settings > Power > Advanced (KDE). 80% is a good default.
- **Refresh rate / VRR:** System Settings > Display. Set Adaptive Sync to *Automatic*.
- **KeePassXC:** Settings > SSH Agent > enable; Settings > Secret Service Integration > enable.
- **Mic:** pick *Noise Canceling Source* as the default input.
- **GNOME only:** install GSConnect from Extension Manager, then log in and re-run `~/.setup/install.sh gnome` once so the GNOME settings apply.

`install.sh` is safe to re-run at any time: it skips everything already done.

---

## What gets installed

Everything is in plain lists. Edit them, re-run `install.sh`.

| File | What |
|---|---|
| [`common.txt`](../.setup/common.txt) | shell, CLI, apps, drivers, system services, fonts |
| [`kde.txt`](../.setup/kde.txt) | Plasma + KDE apps |
| [`gnome.txt`](../.setup/gnome.txt) | GNOME + GNOME apps |
| [`flatpak.txt`](../.setup/flatpak.txt) | Flathub apps (per-user) |

### Apps

| Use | Pick | KDE | GNOME |
|---|---|---|---|
| Terminal | Ghostty (GPU) | ✓ | ✓ |
| Browser | Zen (Flatpak) + Chromium | ✓ | ✓ |
| Passwords, TOTP, SSH keys | KeePassXC | ✓ | ✓ |
| Office | LibreOffice | ✓ | ✓ |
| Files | | Dolphin | Nautilus |
| Images | | Gwenview | Loupe |
| PDF | | Okular | Papers |
| Video | mpv | Haruna | Celluloid |
| Music | | Elisa | Amberol |
| Camera | | Kamoso | Snapshot |
| Screenshots | | Spectacle | built-in |
| Phone link | | KDE Connect | GSConnect |

The rule: the desktop's own app for files, images, PDFs and screenshots (it matches the theme and uses the GPU); my own pick only where it matters.

**Browsers:** Zen (Flatpak, Firefox engine) and Chromium (pacman). Both decode video on the AMD GPU (Chromium since 143, no flags; check `chrome://gpu`).
KeePassXC autofill: works in Chromium out of the box (KeePassXC > Settings > Browser Integration > Chromium). Zen as a Flatpak is sandboxed, so the KeePassXC-Browser extension can't reach KeePassXC without extra setup. In Zen, copy from KeePassXC instead (`Ctrl+B` username, `Ctrl+C` password; the clipboard clears itself). Auto-Type is not an option: it does not work on Wayland.

### CLI

`zsh` + `starship`, `tmux`, `neovim`, `mise`, `git` + `delta` + `lazygit`, `gh`, `ripgrep`, `fd`, `fzf`, `zoxide`, `bat`, `eza`, `dust`, `btop`, `jq`, `yq`, `xh`, `tldr` (tealdeer), `powertop`.

**Network + DNS:** `dig`/`host` (bind), `doggo` (modern dig, DoH/DoT), `mtr` (live traceroute), `gping` (ping graph), `nmap`, `nc` (openbsd-netcat), `iperf3`, `tcpdump`, `ethtool`, `bandwhich` (per-process bandwidth), `whois`, `wg` (wireguard-tools).

### Containers: rootless Podman

`podman` runs containers as your user (no daemon, no root). `podman-docker` adds a `docker` command that calls it, and `podman.socket` (user service) provides the Docker API, with `DOCKER_HOST` pointing at it, so `docker-compose`, `lazydocker` and testcontainers work unchanged.

```sh
docker run --rm -it alpine sh          # = podman run …
docker-compose up -d                   # uses podman.socket
lazydocker                             # TUI
dive <image>                           # inspect image layers
```

Short image names resolve on Docker Hub ([`~/.config/containers/registries.conf`](../.config/containers/registries.conf)). Rootless needs `/etc/subuid` + `/etc/subgid` entries for your user; `useradd` creates them, so a fresh archinstall user already has them.

### Dev tools: mise

Global tools are in [`~/.config/mise/config.toml`](../.config/mise/config.toml): `node` (LTS), `pnpm`, `uv`, `claude`. Projects pin their own versions in a `mise.toml`:

```toml
[tools]
node = "22"
pnpm = "9"

[tasks]
dev = "pnpm dev"
```

Python: `uv python install`, `uv venv`. Updating: `mise up`; cleaning: `mise prune`.

Rule of thumb: **pacman** for the system and CLI tools the shell needs, **mise** for language runtimes and dev tools, **Flatpak** for GUI apps pacman doesn't have, **AppImage** only as a last resort.

### System setup done by `install.sh`

- **Services:** bluetooth, cups (printing), `fstrim.timer` (SSD TRIM), `paccache.timer` (keeps 3 old package versions for downgrades), `reflector.timer` (mirrors), `ssh-agent.socket` + `podman.socket` (user).
- **Firewall:** `ufw`, deny incoming; KDE Connect / GSConnect ports `1714–1764` TCP+UDP open.
- **zram:** Arch wiki tuning for in-memory swap (`swappiness=180`, `page-cluster=0`, watermarks).
- **TRIM through LUKS2:** `cryptsetup --allow-discards --persistent refresh`, stored in the disk header (no kernel option).
- **KDE:** KWallet off (KeePassXC is the secret store), Ghostty as default terminal, `Meta+Return` opens Ghostty.
- **GNOME:** `adw-gtk3` theme for GTK3 apps, `Super+Return` opens Ghostty.
- **Shell:** login shell switched to zsh.
- Then the machine script, `~/.setup/$(hostname).sh`.

---

## Daily use

```sh
# dotfiles (dot is an alias, so tab completion works like plain git)
dot status
dot add ~/.config/foo/config
dot commit -m "foo: ..."
dot push
lazydot                     # lazygit on the dotfiles repo

# updates
sudo pacman -Syu
mise up
flatpak update
fwupdmgr refresh && fwupdmgr get-updates

# power
powerprofilesctl                       # or the battery icon
powerprofilesctl set performance       # on AC, for heavy work
sudo powertop                          # see real battery draw (W)
```

Only files you `dot add` are tracked (`status.showUntrackedFiles no`), so the rest of `$HOME` is ignored.

### Keys

| Key | Does |
|---|---|
| `Meta+Return` / `Super+Return` | Ghostty |
| `Ctrl+F` (zsh), `prefix f` (tmux) | tmux-sessionizer: fuzzy-pick a project, open/switch session |
| `Ctrl+R` / `Ctrl+T` / `Alt+C` | fzf: history / file / cd |
| `z <part>` | zoxide jump |

---

## Layout

```
~/.github/README.md                    this file
~/.setup/
  bootstrap.sh                         clone + checkout + install (fresh machine)
  install.sh                           ./install.sh kde|gnome
  common.txt kde.txt gnome.txt flatpak.txt
  tuf-a15.sh t14-amd.sh                  per-machine fixes (named after the hostname)
~/.zshenv                              every zsh: ZDOTDIR, PATH, EDITOR. Silent and tiny
~/.config/zsh/.zshrc                   interactive zsh
~/.config/environment.d/10-env.conf    desktop session env: PATH, EDITOR, SSH_AUTH_SOCK
~/.config/git/{config,ignore}          git (identity in ~/.config/git/local, untracked)
~/.config/tmux/tmux.conf
~/.config/nvim/                        Neovim 0.12, vim.pack, lockfile committed
~/.config/ghostty/                     config.ghostty + Breeze Light theme
~/.config/starship.toml
~/.config/mise/config.toml
~/.config/pipewire/pipewire.conf.d/99-mic-denoise.conf
~/.config/containers/registries.conf   podman: short names → docker.io
~/.local/bin/tmux-sessionizer
```

### Why `.zshenv` is so small

AI coding agents and scripts start **non-interactive** zsh, which still reads `.zshenv`. Anything that prints, prompts or is slow there breaks them. So `.zshenv` only sets paths; prompt, plugins and aliases live in `.zshrc`, which only interactive shells read. Scripts in this repo are POSIX `sh`.

### Why `environment.d` and not `.zprofile`

Shell profiles only reach terminals. KeePassXC, the editor launched from the menu and everything else the desktop starts get their environment from systemd's `environment.d`. That is where `SSH_AUTH_SOCK` must be set for KeePassXC's SSH agent integration to work everywhere.

---

## Per-machine notes

### `tuf-a15`: ASUS TUF Gaming A15

Hybrid graphics: the laptop panel and USB-C ports run on the AMD iGPU; **HDMI is wired to the NVIDIA GPU**.

What [`tuf-a15.sh`](../.setup/tuf-a15.sh) does:

| Change | Why |
|---|---|
| `nvidia-open nvidia-utils nvidia-prime nvtop` | driver, `prime-run`, GPU monitor |
| remove `libva-nvidia-driver` | browsers otherwise decode video on NVIDIA and keep it awake (~12 W idle) |
| `vulkan-radeon` (common.txt) | without it the only Vulkan device is NVIDIA, so Vulkan apps wake it |
| `acpi_backlight=native` | kernel picked `nvidia_wmi_ec_backlight` and skipped amdgpu's, so brightness did nothing |
| udev names + `KWIN_DRM_DEVICES` (AMD first) | KWin and Xwayland otherwise render on NVIDIA and keep it awake (~13 W idle). Written to `~/.config/plasma-workspace/env/gpu.sh`, not tracked (this laptop only) |
| enable `nvidia-powerd` | Dynamic Boost on AC: GPU 60 W → up to 95 W |

Already handled by Arch, nothing to do: runtime D3 (GPU powers off when idle), video memory saved on suspend (driver 595+; `nvidia-suspend/resume/hibernate` services correctly stay **disabled**), `nvidia-drm` modeset.

**Check the NVIDIA GPU sleeps** (after reboot, nothing GPU-heavy open):

```sh
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status   # → suspended
nvidia-smi --query-gpu=power.draw --format=csv                # wakes it briefly; fine
```

If it stays `active`, see what holds it: `sudo fuser -v /dev/nvidia* /dev/dri/card0`.

**Using the NVIDIA GPU**

| Workload | How |
|---|---|
| Games | Steam launch option: `prime-run %command%` |
| Blender, DaVinci, 3D | `prime-run <app>` |
| CUDA / PyTorch | nothing: CUDA finds the GPU itself. pip/uv wheels bring their own CUDA libs; install `cuda` only to compile with `nvcc` |
| Everything else | stays on AMD (lower power, smoother) |

A CUDA process (including an idle Jupyter kernel) keeps the GPU awake: close it when done. `nvtop` shows what is using it.

**Max performance:** plug in, `powerprofilesctl set performance` (ASUS performance mode: higher CPU limits, faster fans), Dynamic Boost does the GPU. On battery the firmware caps power regardless.

**Battery** (47.5 Wh design): NVIDIA asleep is the big win. Expect ~4–5 h coding at 144 Hz, ~5.5–6 h at 60 Hz + power-saver. Switch refresh: `kscreen-doctor output.eDP-1.mode.1920x1080@60`. External monitor on battery: use USB-C (AMD), not HDMI (NVIDIA).

**ASUS tools:** not needed. Power modes go through power-profiles-daemon, charge limit through Plasma, keyboard backlight through KDE. `asusctl` (in the Arch repos) is only for hand-tuning power limits (`nv_dynamic_boost`, PPT). If you add it, leave mode switching to power-profiles-daemon.

### `t14-amd`: ThinkPad T14 Gen 1 AMD

**BIOS first:**
- Config > Power > Sleep State = **Linux** (real S3 sleep; s2idle drains more).
- **Never enroll your own Secure Boot keys**: per the Arch wiki this bricks the board.
- Firmware: `fwupdmgr update` (BIOS + fingerprint reader via LVFS). The wiki notes BIOS 1.30 caused heavy drain in suspend; read the release notes before updating.

What [`t14-amd.sh`](../.setup/t14-amd.sh) does: `fprintd` (fingerprint), `alsa-utils` (mic LED stuck on), `mem_sleep_default=deep` when the BIOS offers S3, and a warning if the CPU isn't using `amd-pstate`.

No ThinkPad tools needed: `thinkpad_acpi` + power-profiles-daemon + Plasma's charge limit (start and end thresholds, e.g. 75–80%) cover it. Hibernate is skipped: resume is unreliable on this model.

**Only if you hit them:**

| Problem | Fix |
|---|---|
| Wi-Fi drops (Intel AX200) | `echo 'options iwlwifi 11n_disable=8' \| sudo tee /etc/modprobe.d/iwlwifi.conf` |
| Left click dead after resume | add `psmouse.synaptics_intertouch=0` to `/etc/kernel/cmdline`, `sudo mkinitcpio -P` |

#### T14: `/data` drive

Second LUKS disk, mounted at `/data`:

```sh
# keyfile so it unlocks at boot without a second passphrase
sudo dd if=/dev/urandom of=/etc/cryptsetup-keys.d/data.key bs=512 count=4
sudo chmod 600 /etc/cryptsetup-keys.d/data.key
sudo cryptsetup luksAddKey /dev/disk/by-uuid/<UUID> /etc/cryptsetup-keys.d/data.key

echo 'data UUID=<UUID> /etc/cryptsetup-keys.d/data.key discard' | sudo tee -a /etc/crypttab
echo '/dev/mapper/data /data ext4 noatime,nofail 0 2'           | sudo tee -a /etc/fstab
sudo mkdir -p /data && sudo systemctl daemon-reload && sudo mount /data
```

`<UUID>`: `lsblk -f` → the `crypto_LUKS` partition.

### Kernel options

Machine scripts add kernel options with `kernel_param <option>`. How it stays safe:

- The boot is a **unified kernel image** (systemd-boot + mkinitcpio `default_uki`). Its options come from `/etc/kernel/cmdline`, one line; `kernel_param` appends to that line only.
- An option that is already there is skipped, so re-running changes nothing.
- The first edit saves the original as `/etc/kernel/cmdline.orig`.
- Each change is printed, and the image is rebuilt **once** at the end (`mkinitcpio -P`), only if something changed.

Check after reboot: `cat /proc/cmdline`.

Undo: delete the word from `/etc/kernel/cmdline` (or `sudo cp /etc/kernel/cmdline.orig /etc/kernel/cmdline`), then `sudo mkinitcpio -P`.

If an option stops the machine from booting:
1. In the systemd-boot menu, press `e` on the entry and remove the option for this one boot (works while Secure Boot is off).
2. Or boot the Arch USB, `cryptsetup open /dev/nvme0n1p2 root`, `mount /dev/mapper/root /mnt`, `mount /dev/nvme0n1p1 /mnt/boot`, `arch-chroot /mnt`, fix the file, `mkinitcpio -P`.

Options in use:

| Option | Machine | Why |
|---|---|---|
| `acpi_backlight=native` | tuf-a15 | brightness: use amdgpu's backlight, not `nvidia_wmi_ec_backlight` |
| `mem_sleep_default=deep` | t14-amd | S3 sleep instead of s2idle (needs BIOS Sleep State = Linux) |

### A new machine

1. Pick a hostname, e.g. `newbox`: lowercase, digits and `-`.
2. Add `~/.setup/newbox.sh` (sourced by `install.sh`; can use `kernel_param` and `say`).
3. Add a row to the table at the top.

---

## Theming

Use **Breeze** on KDE and **Adwaita** on GNOME. No extra themes; dark mode reaches apps through the desktop portal.

| App type | KDE | GNOME |
|---|---|---|
| Qt | native Breeze | follows dark mode via the portal |
| GTK 4 | Breeze colours (`breeze-gtk`, in `plasma-meta`) | native Adwaita |
| GTK 3 | `breeze-gtk` | `adw-gtk3` (set by `install.sh`) |
| Flatpak GTK | `org.gtk.Gtk3theme.Breeze` (installed) | `org.gtk.Gtk3theme.adw-gtk3{,-dark}` (installed) |
| Flatpak Qt/KDE | follows the portal | follows the portal |
| Electron | Wayland by default since Electron 38.2; dark mode via portal. Old apps: `--ozone-platform=wayland` in `~/.config/<app>-flags.conf` | same; add `--enable-features=WaylandWindowDecorations` if the title bar is missing |
| Chromium / Brave | flags in `~/.config/chromium-flags.conf` / `brave-flags.conf` | same |
| AppImage | bundles its own toolkit; theming varies. `fuse2` runs them, Gear Lever adds them to the menu | same |

Flatpak cursor wrong? `flatpak --user override --filesystem=xdg-data/icons:ro` (the Arch wiki has more under Flatpak).

---

## Troubleshooting

| Problem | Check |
|---|---|
| `ssh-add -l`: "Could not open a connection" | log out and in once (environment.d); `systemctl --user status ssh-agent.socket`; `echo $SSH_AUTH_SOCK` |
| Brightness slider does nothing | `ls /sys/class/backlight/`: should show `amdgpu_bl*`; check `acpi_backlight=native` in `/etc/kernel/cmdline` |
| NVIDIA never sleeps | `runtime_status` (above); `fuser -v /dev/nvidia*`; is `libva-nvidia-driver` back? |
| Kernel option not applied | `cat /proc/cmdline`; after editing `/etc/kernel/cmdline` run `sudo mkinitcpio -P` (see [Kernel options](#kernel-options)) |
| `docker`/compose: "Cannot connect" | `systemctl --user status podman.socket`; `echo $DOCKER_HOST` (log out and in once) |
| TRIM | `lsblk -D`: `DISC-GRAN` must not be `0B` on the `root` mapper |
| zsh slow to start | `time zsh -i -c exit` (aim < 100 ms) |
| Broken update | boot the live USB, `arch-chroot`, downgrade from `/var/cache/pacman/pkg` with `pacman -U` |

Sources used for the machine notes: Arch wiki pages *NVIDIA/Tips and tricks*, *PRIME*, *Backlight*, *Zram*, *dm-crypt/Specialties*, *Lenovo ThinkPad T14 (AMD) Gen 1*, *KDE* (KDE Connect), *Wayland* (Electron), *Flatpak*, *Power management*.
