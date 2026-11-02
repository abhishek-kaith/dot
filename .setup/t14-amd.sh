# Lenovo ThinkPad T14 Gen 1 AMD (Ryzen 4000 "Renoir"). Sourced by install.sh.
# Arch wiki: Lenovo ThinkPad T14 (AMD) Gen 1.
#
# BIOS, before anything else:
#   Config > Power > Sleep State = Linux   (real S3 sleep)
#   Never enroll your own Secure Boot keys: the wiki says it bricks this model.

say "fingerprint reader + mic LED fix"
# fprintd: the Synaptics reader works; `fwupdmgr update` updates its firmware.
# alsa-utils: stops the mic LED from staying on.
sudo pacman -S --needed fprintd alsa-utils

if grep -qw deep /sys/power/mem_sleep; then
    kernel_param mem_sleep_default=deep
else
    echo "!! S3 sleep not offered: set BIOS Config > Power > Sleep State = Linux, then re-run"
fi

driver=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo unknown)
case $driver in
    amd-pstate*) ;;
    *) echo "!! CPU driver is '$driver', not amd-pstate: update the BIOS (fwupdmgr update)" ;;
esac

# /data (second encrypted disk) is machine-specific, so it is not automated.
# See "T14: /data drive" in ~/.github/README.md.

# Only if you see the problem (add with kernel_param, or modprobe.d):
#   Wi-Fi drops (Intel AX200):  echo 'options iwlwifi 11n_disable=8' | sudo tee /etc/modprobe.d/iwlwifi.conf
#   Left click dead after resume: kernel_param psmouse.synaptics_intertouch=0
# Hibernate is skipped on purpose: resume is unreliable on this model.
