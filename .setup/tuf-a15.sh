# ASUS TUF Gaming A15 (FA506NCG): Ryzen 7 7445HS + Radeon 740M, RTX 3050 Laptop.
# Sourced by install.sh (uses its kernel_param and say helpers).
# Hybrid graphics: the panel and USB-C are on the AMD GPU, HDMI on the NVIDIA one
# (HDMI unused: KWin is AMD-only, see below).
# `gpu-mode eco|hybrid` (~/.local/bin) turns the NVIDIA GPU off/on in firmware.

say "NVIDIA driver + prime-run + nvtop"
sudo pacman -S --needed nvidia-open nvidia-utils nvidia-prime nvtop

# libva-nvidia-driver makes browsers decode video on the NVIDIA GPU and keeps it
# awake (~12 W at idle). The AMD GPU decodes everything this laptop needs.
if pacman -Q libva-nvidia-driver >/dev/null 2>&1; then
    say "removing libva-nvidia-driver"
    sudo pacman -Rns libva-nvidia-driver
fi

# Brightness: the kernel picks nvidia_wmi_ec_backlight and skips amdgpu's, so
# the slider changes nothing (Arch wiki: Backlight, acpi_backlight=native).
kernel_param acpi_backlight=native

# KWin runs on the AMD GPU only and never touches the NVIDIA one, so nothing in
# the desktop session holds it: `gpu-mode eco|hybrid` switches instantly, and in
# hybrid the GPU is free for prime-run / CUDA. Trade-off: no HDMI (wired to
# NVIDIA); USB-C displays work (AMD). Two parts, both needed:
#   KWIN_DRM_DEVICES  which GPUs KWin drives (Arch wiki, KDE). card0/card1 can
#                     swap between boots, so the AMD GPU (0000:05:00.0) gets a
#                     stable name.
#   EGL vendor        glvnd otherwise also loads NVIDIA's EGL into KWin, which
#                     opens /dev/nvidia0 even with an AMD-only device list. Set on
#                     KWin's own unit, so apps (prime-run) are unaffected.
say "KWin: AMD GPU only"
sudo tee /etc/udev/rules.d/61-gpu-names.rules >/dev/null <<'EOF'
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:05:00.0", SYMLINK+="dri/amd-igpu"
EOF
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=drm
# Machine-specific, so written here and NOT tracked in the dotfiles repo.
mkdir -p "$HOME/.config/plasma-workspace/env"
cat > "$HOME/.config/plasma-workspace/env/gpu.sh" <<'EOF'
#!/bin/sh
# Written by ~/.setup/tuf-a15.sh: KWin drives the AMD iGPU only.
export KWIN_DRM_DEVICES=/dev/dri/amd-igpu
EOF
chmod +x "$HOME/.config/plasma-workspace/env/gpu.sh"
mkdir -p "$HOME/.config/systemd/user/plasma-kwin_wayland.service.d"
cat > "$HOME/.config/systemd/user/plasma-kwin_wayland.service.d/egl-mesa.conf" <<'EOF'
# Written by ~/.setup/tuf-a15.sh: KWin loads only Mesa's EGL (AMD), so it never
# opens the NVIDIA GPU. Apps don't inherit this; prime-run keeps working.
[Service]
Environment=__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
EOF

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
