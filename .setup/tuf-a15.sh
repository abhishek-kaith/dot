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
# in ~/.config/niri/hosts/tuf-a15.kdl (render-drm-device).
# niri also leaves the NVIDIA GPU alone (no HDMI) unless `gpu-mode hdmi on`, so
# it never keeps it awake and eco/hybrid switch while logged in. Default: off.
# The choice is ~/.config/niri/nvidia.kdl (not tracked); only made if missing.
if [ "$de" = niri ] && [ ! -e "$HOME/.config/niri/nvidia.kdl" ]; then
    "$HOME/.local/bin/gpu-mode" hdmi off
fi

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
