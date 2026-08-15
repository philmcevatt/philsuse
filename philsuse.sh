#!/usr/bin/env bash
# philsuse.sh — v0.0.11
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

echo "=== 6. Printing/scanning, Samba client, Snapper GUI, Discover, Myrlyn ==="
# Deliberate additions confirmed against a full Agama KDE install — comment out
# any block below you don't want on a given machine (e.g. laptop vs desktop).
# Printing/scanning: driver packages only, absent from the minimal base.
sudo zypper install -y \
    gutenprint \
    sane-backends \
    libKSaneCore6-1 \
    libKSaneWidgets6 \
    libksane-icons \
    libksane-lang
# Samba: deliberately OFF for now — no network/NAS set up yet, and Tumbleweed
# may not even be the distro in use by the time one exists. Uncomment if/when
# needed (client-only — not installing samba/samba-dcerpc/samba-python3 server
# capability). Unrelated to the /mnt/d and /mnt/e ntfs3 fstab mounts either way.
# sudo zypper install -y \
#     samba-client \
#     samba-client-libs \
#     cifs-utils
# Snapper: core + zypp-plugin + snapperd (D-Bus service) are all already
# installed by patterns-kde-kde_plasma (confirmed — snapperd ships inside the
# snapper package, not separately). snapper-cleanup.timer and
# snapper-timeline.timer are already enabled too. Only the YaST GUI module is
# actually missing.
sudo zypper install -y \
    yast2-snapper
# Discover: software-centre GUI, useful for Flatpak installs and troubleshooting
# guides that assume it exists.
sudo zypper install -y \
    discover6 \
    discover6-backend-flatpak \
    discover6-backend-fwupd \
    discover6-backend-packagekit \
    discover6-notifier
# Myrlyn: successor to YaST's software-management module.
sudo zypper install -y \
    myrlyn

echo "=== 7. Installing Cockpit, Firefox & Custom Tools ==="
sudo zypper install -y \
    cockpit \
    cockpit-system \
    cockpit-podman \
    cockpit-client-launcher \
    firefox \
    git \
    curl \
    fastfetch

echo "=== 8. Enabling Cockpit Service ==="
sudo systemctl enable --now cockpit.socket

echo "=== 9. Packman codecs via opi ==="
# opi adds the Packman repo (higher priority than official repos), runs
# zypper dist-upgrade --from packman --allow-vendor-change, then installs the
# gstreamer-plugins-{good,bad,ugly} codec set. Confirmed against opi's official
# GitHub README and the openSUSE docs codecs page — -n is opi's documented
# non-interactive flag.
# NOTE — deliberate trade-off, not a bug: once run, Packman becomes the sole
# permitted provider for any package this touches, so openSUSE's own repos will
# no longer update those specific packages. That's opi's/Packman's normal,
# documented behaviour for codecs, not something to "fix".
sudo zypper install -y opi
opi -n codecs

echo "=== 10. Fixing Bash multi-line paste (bracketed paste mode) ==="
# openSUSE's base doesn't enable Readline's bracketed paste mode by default
# (unlike e.g. Fedora) — without it, Bash executes each line of a pasted
# multi-line block as it's received instead of waiting, which is dangerous for
# anything with a placeholder (<your username here>) meant to be edited first.
if ! grep -qxF 'set enable-bracketed-paste on' ~/.inputrc 2>/dev/null; then
    echo 'set enable-bracketed-paste on' >> ~/.inputrc
fi

echo "=== Done! Reboot into the minimal KDE environment. ==="
echo "--- After reboot, sanity-check: is there a network widget, and does resolution/scaling look right? ---"
echo "--- Those are exactly the kind of things --no-recommends can silently drop. ---"
