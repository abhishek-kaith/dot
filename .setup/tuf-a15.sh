# ASUS TUF Gaming A15 (FA506NCG): Ryzen 7 7445HS + Radeon 740M, RTX 3050 Laptop.
# Sourced by install.sh (uses its kernel_param and say helpers).
# Hybrid graphics: the panel and USB-C are on the AMD GPU, HDMI on the NVIDIA one.

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

# Dynamic Boost: lets the GPU go from 60 W up to 95 W on AC by borrowing CPU
# budget. Does nothing on battery.
sudo systemctl enable nvidia-powerd.service

# NOT needed (driver 595+, Arch wiki NVIDIA/Tips and tricks): nvidia-suspend,
# nvidia-resume and nvidia-hibernate stay disabled; the driver saves video
# memory itself. Runtime D3 (GPU off when idle) is on by default.
