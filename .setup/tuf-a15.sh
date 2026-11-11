# ASUS TUF Gaming A15 (Radeon 740M + RTX 3050). Sourced by install.sh.

say "NVIDIA driver + prime-run + nvtop"
# nvidia-open fits the stock kernel only; others need -dkms + headers.
kernels=$(pacman -Qq linux linux-zen linux-lts linux-hardened 2>/dev/null || true)
if [ "$kernels" = linux ]; then
    nvdriver=nvidia-open
else
    nvdriver="nvidia-open-dkms $(printf '%s-headers ' $kernels)"
fi
# shellcheck disable=SC2086  # one word per package
sudo pacman -S --needed $nvdriver nvidia-utils nvidia-prime nvtop

# libva-nvidia-driver keeps the GPU awake (~12 W); AMD decodes video fine.
if pacman -Q libva-nvidia-driver >/dev/null 2>&1; then
    say "removing libva-nvidia-driver"
    sudo pacman -Rns libva-nvidia-driver
fi

# Brightness: use amdgpu's backlight, not nvidia_wmi_ec_backlight.
kernel_param acpi_backlight=native

# A `gpu-mode eco` scheduled while the GPU was in use runs at the next boot,
# before the login screen. Root-owned copy of the eco steps (root never runs
# files from $HOME).
say "gpu-mode: eco at boot when scheduled"
sudo mkdir -p /usr/local/lib /var/lib/gpu-mode
sudo tee /usr/local/lib/gpu-mode-boot >/dev/null <<'EOF'
#!/bin/sh
# Written by ~/.setup/tuf-a15.sh; run by gpu-mode-boot.service.
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

# Dynamic Boost (GPU 60 -> 95 W on AC); skipped in eco.
sudo mkdir -p /etc/systemd/system/nvidia-powerd.service.d
printf '[Unit]\nConditionPathExists=/sys/bus/pci/devices/0000:01:00.0\n' |
    sudo tee /etc/systemd/system/nvidia-powerd.service.d/only-with-gpu.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable nvidia-powerd.service

# Not needed (driver 595+): nvidia-suspend/resume/hibernate stay disabled.
