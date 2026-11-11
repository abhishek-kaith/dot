# ASUS TUF Gaming A15 (FA506NCG): Ryzen 7 7445HS + Radeon 740M, RTX 3050 Laptop.
# Sourced by install.sh (uses its kernel_param and say helpers).
# Hybrid graphics: the panel and USB-C are on the AMD GPU, HDMI on the NVIDIA one.
# `gpu-mode eco|hybrid` (~/.local/bin) turns the NVIDIA GPU off/on in firmware.

say "NVIDIA driver + prime-run + nvtop"
# nvidia-open is built for the stock `linux` kernel only. Any other kernel
# (linux-zen, linux-lts, ...) needs nvidia-open-dkms plus that kernel's headers.
kernels=$(pacman -Qq linux linux-zen linux-lts linux-hardened 2>/dev/null || true)
if [ "$kernels" = linux ]; then
    nvdriver=nvidia-open
else
    nvdriver="nvidia-open-dkms $(printf '%s-headers ' $kernels)"
fi
# shellcheck disable=SC2086  # one word per package
sudo pacman -S --needed $nvdriver nvidia-utils nvidia-prime nvtop

# libva-nvidia-driver makes browsers decode video on the NVIDIA GPU and keeps it
# awake (~12 W at idle). The AMD GPU decodes everything this laptop needs.
if pacman -Q libva-nvidia-driver >/dev/null 2>&1; then
    say "removing libva-nvidia-driver"
    sudo pacman -Rns libva-nvidia-driver
fi

# Brightness: the kernel picks nvidia_wmi_ec_backlight and skips amdgpu's, so
# the slider changes nothing (Arch wiki: Backlight, acpi_backlight=native).
kernel_param acpi_backlight=native

# Render on the AMD GPU, not the NVIDIA one (else ~13 W more at idle): one line
# in ~/.config/niri/hosts/tuf-a15.kdl (render-drm-device). In hybrid niri also
# opens the NVIDIA GPU, only for the HDMI port (as KWin did).

# `gpu-mode eco` while niri (or anything) has the NVIDIA GPU open is scheduled:
# this runs it at the next boot, before the login screen, when nothing holds the
# GPU. Root-owned copy of just the eco steps from ~/.local/bin/gpu-mode, so root
# never runs a file from $HOME.
say "gpu-mode: eco at boot when scheduled"
sudo mkdir -p /usr/local/lib /var/lib/gpu-mode
sudo tee /usr/local/lib/gpu-mode-boot >/dev/null <<'EOF'
#!/bin/sh
# Written by ~/.setup/tuf-a15.sh. Run by gpu-mode-boot.service when
# /var/lib/gpu-mode/pending exists (`gpu-mode eco` while the GPU was in use).
set -eu
attr=/sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable
rm -f /var/lib/gpu-mode/pending
[ "$(cat "$attr/current_value")" = 1 ] && exit 0
if [ -e /sys/bus/pci/devices/0000:01:00.0 ]; then
    modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia
    for dev in /sys/bus/pci/devices/0000:01:00.*; do
        echo 1 >"$dev/remove"
    done
fi
echo 1 >"$attr/current_value"
echo "gpu-mode: eco (NVIDIA GPU off)"
EOF
sudo chmod 755 /usr/local/lib/gpu-mode-boot
sudo tee /etc/systemd/system/gpu-mode-boot.service >/dev/null <<'EOF'
# Written by ~/.setup/tuf-a15.sh: apply a scheduled `gpu-mode eco` at boot.
[Unit]
Description=Switch the NVIDIA GPU off (scheduled gpu-mode eco)
ConditionPathExists=/var/lib/gpu-mode/pending
After=systemd-modules-load.service
Before=display-manager.service nvidia-powerd.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/gpu-mode-boot

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable gpu-mode-boot.service

# Dynamic Boost: lets the GPU go from 60 W up to 95 W on AC by borrowing CPU
# budget. Does nothing on battery. Skipped quietly in gpu-mode eco (no GPU).
sudo mkdir -p /etc/systemd/system/nvidia-powerd.service.d
printf '[Unit]\nConditionPathExists=/sys/bus/pci/devices/0000:01:00.0\n' |
    sudo tee /etc/systemd/system/nvidia-powerd.service.d/only-with-gpu.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable nvidia-powerd.service

# NOT needed (driver 595+, Arch wiki NVIDIA/Tips and tricks): nvidia-suspend,
# nvidia-resume and nvidia-hibernate stay disabled; the driver saves video
# memory itself. Runtime D3 (GPU off when idle) is on by default, but on this
# laptop the firmware's NVPCF notifications wake the GPU again within a second
# (NVIDIA open-gpu-kernel-modules #1300). Hence gpu-mode eco for battery days.
