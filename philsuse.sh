#!/usr/bin/env bash
# philsuse.sh — v0.0.5
# Strategy change: install the base with recommends ON. --no-recommends was the
# root cause of nearly every issue in v0.0.1-v0.0.4 (missing sddm-config-wayland,
# sddm-wayland-miriway, wallpaper backend, etc.) — those are all recommends of
# sddm/patterns-kde-kde_plasma, not hard requires. Confirmed by LGL's opensuse
# script never using --no-recommends at all. Get a known-working desktop first,
# strip unwanted stuff (games, PIM, office) afterward in a separate pass.
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
sudo zypper install -y \
    patterns-kde-kde_plasma \
    sddm-qt6 \
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

echo "=== 4. Setting SDDM to use Wayland (greeter + default session), no X11 stack ==="
# openSUSE's default sddm config (00-general.conf) sets no DisplayServer=, so SDDM
# falls back to its compiled-in X11 default to draw the greeter itself — and
# DefaultSession points at xsessions/default.desktop, which doesn't exist since
# we're deliberately not installing xorg-x11-server. Drop-ins in /etc/sddm.conf.d
# load after the package defaults in /usr/lib/sddm/sddm.conf.d and override them.
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/10-wayland-default.conf > /dev/null <<'EOF'
[General]
DisplayServer=wayland
DefaultSession=/usr/share/wayland-sessions/plasmawayland.desktop
EOF

echo "=== 5. Enabling SDDM Display Manager and Graphical Boot ==="
# Agama's minimal role can leave /etc/systemd/system/display-manager.service
# already symlinked to something else (seen: display-manager-legacy.service).
# systemctl enable refuses to clobber an existing symlink without --force.
if [ -e /etc/systemd/system/display-manager.service ]; then
    echo "--- Existing display-manager.service symlink found, pointing to: $(readlink -f /etc/systemd/system/display-manager.service) ---"
fi
sudo systemctl enable --force sddm
sudo systemctl set-default graphical.target

echo "=== 6. Installing Cockpit & Custom Tools (no recommends, this install only) ==="
sudo zypper install -y \
    cockpit \
    cockpit-system \
    cockpit-podman \
    git \
    curl \
    fastfetch

echo "=== 7. Enabling Cockpit Service ==="
sudo systemctl enable --now cockpit.socket

echo "=== Done! Reboot into the minimal KDE environment. ==="
echo "--- After reboot, sanity-check: is there a network widget, and does resolution/scaling look right? ---"
echo "--- Those are exactly the kind of things --no-recommends can silently drop. ---"
