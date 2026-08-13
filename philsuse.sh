#!/usr/bin/env bash
# philsuse.sh — v0.0.1
# Base KDE Plasma install for openSUSE Tumbleweed (netinst, Agama, minimal/Server role)
# Scope: bare minimum working Plasma desktop only. Nvidia, flatpaks, firewall,
# gaming stack, guest tools etc. are separate later scripts.
set -e

echo "=== 1. Refreshing Repositories ==="
sudo zypper ref

echo "=== 2. Installing Bare Minimum KDE Plasma Environment (no recommends, this install only) ==="
# --no-recommends is scoped to this command only — NOT a permanent zypp.conf change.
# Future installs (nvidia, gaming stack, etc.) get recommends as normal unless you
# explicitly pass --no-recommends again.
sudo zypper install --no-recommends -y \
    patterns-kde-kde_plasma \
    sddm \
    dolphin \
    konsole \
    kate

echo "=== 3. Installing NetworkManager explicitly ==="
# --no-recommends above means plasma-nm / NetworkManager itself may not have been
# pulled in as a hard dependency of the plasma pattern. A minimal/Server role
# install can also default to wicked instead of NetworkManager. Belt and braces:
sudo zypper install -y \
    NetworkManager \
    NetworkManager-branding-openSUSE \
    plasma6-nm

if systemctl is-active --quiet wicked; then
    echo "--- wicked is active, switching to NetworkManager ---"
    sudo systemctl disable --now wicked
fi
sudo systemctl enable --now NetworkManager

echo "=== 4. Enabling SDDM Display Manager and Graphical Boot ==="
# Agama's minimal role can leave /etc/systemd/system/display-manager.service
# already symlinked to something else (seen: display-manager-legacy.service).
# systemctl enable refuses to clobber an existing symlink without --force.
if [ -e /etc/systemd/system/display-manager.service ]; then
    echo "--- Existing display-manager.service symlink found, pointing to: $(readlink -f /etc/systemd/system/display-manager.service) ---"
fi
sudo systemctl enable --force sddm
sudo systemctl set-default graphical.target

echo "=== 5. Installing Cockpit & Custom Tools (no recommends, this install only) ==="
sudo zypper install --no-recommends -y \
    cockpit \
    cockpit-system \
    cockpit-podman \
    git \
    curl \
    fastfetch

echo "=== 6. Enabling Cockpit Service ==="
sudo systemctl enable --now cockpit.socket

echo "=== Done! Reboot into the minimal KDE environment. ==="
echo "--- After reboot, sanity-check: is there a network widget, and does resolution/scaling look right? ---"
echo "--- Those are exactly the kind of things --no-recommends can silently drop. ---"
