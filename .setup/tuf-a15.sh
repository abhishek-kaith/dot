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

# niri: the same is one line in ~/.config/niri/hosts/tuf-a15.kdl (render-drm-device).
# KWin (and Xwayland with it) otherwise renders on the NVIDIA GPU and keeps it
# awake (~13 W at idle). Arch wiki, KDE: KWIN_DRM_DEVICES, first = render GPU.
# card0/card1 numbers can swap between boots, so pin names by PCI address:
#   0000:05:00.0 = Radeon 740M (panel, USB-C)   0000:01:00.0 = RTX 3050 (HDMI)
# NVIDIA is added second (so HDMI works) only while it exists: gpu-mode eco
# removes it.
if [ "$de" = kde ]; then
    say "KWin: render on the AMD GPU"
    sudo tee /etc/udev/rules.d/61-gpu-names.rules >/dev/null <<'EOF'
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:05:00.0", SYMLINK+="dri/amd-igpu"
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:01:00.0", SYMLINK+="dri/nvidia-dgpu"
EOF
    sudo udevadm control --reload
    sudo udevadm trigger --subsystem-match=drm
    # Machine-specific, so written here and NOT tracked in the dotfiles repo.
    mkdir -p "$HOME/.config/plasma-workspace/env"
    cat > "$HOME/.config/plasma-workspace/env/gpu.sh" <<'EOF'
#!/bin/sh
# Written by ~/.setup/tuf-a15.sh: KWin renders on the AMD iGPU; the NVIDIA GPU
# (HDMI) is added only when it is on (gpu-mode hybrid).
if [ -e /dev/dri/nvidia-dgpu ]; then
    export KWIN_DRM_DEVICES=/dev/dri/amd-igpu:/dev/dri/nvidia-dgpu
else
    export KWIN_DRM_DEVICES=/dev/dri/amd-igpu
fi
EOF
    chmod +x "$HOME/.config/plasma-workspace/env/gpu.sh"
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
