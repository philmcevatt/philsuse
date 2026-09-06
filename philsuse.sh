#!/usr/bin/env bash
set -euo pipefail

# openSUSE Tumbleweed Bootstrap (TTY friendly)
# Goal: Start from openSUSE minimal server (TTY), run once, reboot into KDE Plasma.

# -----------------------------
# Colours
# -----------------------------
GREEN='\033[38;2;0;255;0m'
ORANGE='\033[38;2;255;153;0m'
RED='\033[38;2;255;68;68m'
WHITE='\033[38;2;249;249;249m'
RESET='\033[0m'
BOLD='\033[1m'

section() { printf "\n${BOLD}${GREEN}==> %s${RESET}\n" "$1"; }
info() { printf "${WHITE}%s${RESET}\n" "$1"; }
warn() { printf "${BOLD}${RED}Warning:${RESET} ${WHITE}%s${RESET}\n" "$1"; }
cmdhint() { printf "${ORANGE}%s${RESET}\n" "$1"; }

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    warn "Run with sudo:"
    cmdhint "sudo bash $0"
    exit 1
  fi
}

get_target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf "%s" "${SUDO_USER}"
  else
    printf "%s" "$(logname 2>/dev/null || echo root)"
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

zypper_refresh() {
  zypper -n --gpg-auto-import-keys refresh
}

try_install() {
  # Install packages one-by-one so missing packages do not kill the whole script.
  # Output is NOT suppressed so you see progress.
  local pkg
  for pkg in "$@"; do
    section "Installing: $pkg"
    if zypper -n in -y "$pkg"; then
      info "Installed: $pkg"
    else
      warn "Could not install: $pkg (skipping)"
    fi
  done
}

repo_exists() {
  local alias="$1"
  zypper lr -u | awk '{print $1}' | grep -qx "$alias"
}

add_repo_if_missing() {
  local alias="$1"
  local name="$2"
  local url="$3"
  local priority="${4:-99}"

  if repo_exists "$alias"; then
    info "Repo exists: $alias"
    return 0
  fi

  section "Adding repo: $name"
  if zypper -n ar -f -p "$priority" -n "$name" "$url" "$alias"; then
    info "Added repo: $alias"
  else
    warn "Failed to add repo: $alias (continuing)"
    return 1
  fi
}

detect_opensuse() {
  if [[ ! -r /etc/os-release ]]; then
    warn "Cannot read /etc/os-release"
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  OS_ID="${ID:-}"
  OS_VERSION_ID="${VERSION_ID:-}"

  if [[ "$OS_ID" != "opensuse-tumbleweed" && "$OS_ID" != "opensuse-leap" && "$OS_ID" != "opensuse" ]]; then
    warn "This does not look like openSUSE. ID=${OS_ID}"
    exit 1
  fi

  info "Detected: ${PRETTY_NAME:-openSUSE} (ID=${OS_ID}, VERSION_ID=${OS_VERSION_ID})"
}

setup_official_repos() {
  if [[ "$OS_ID" == "opensuse-tumbleweed" ]]; then
    add_repo_if_missing "repo-oss" "openSUSE-Tumbleweed-Oss" "https://download.opensuse.org/tumbleweed/repo/oss/" 99 || true
    add_repo_if_missing "repo-non-oss" "openSUSE-Tumbleweed-Non-Oss" "https://download.opensuse.org/tumbleweed/repo/non-oss/" 99 || true
    add_repo_if_missing "repo-update" "openSUSE-Tumbleweed-Update" "https://download.opensuse.org/update/tumbleweed/" 99 || true
    add_repo_if_missing "repo-update-non-oss" "openSUSE-Tumbleweed-Update-Non-Oss" "https://download.opensuse.org/update/tumbleweed-non-oss/" 99 || true
  else
    if [[ -z "${OS_VERSION_ID:-}" ]]; then
      warn "VERSION_ID is empty, cannot build Leap repo URLs"
      return 0
    fi
    add_repo_if_missing "repo-oss" "openSUSE-Leap-Oss" "https://download.opensuse.org/distribution/leap/${OS_VERSION_ID}/repo/oss/" 99 || true
    add_repo_if_missing "repo-non-oss" "openSUSE-Leap-Non-Oss" "https://download.opensuse.org/distribution/leap/${OS_VERSION_ID}/repo/non-oss/" 99 || true
    add_repo_if_missing "repo-update" "openSUSE-Leap-Update" "https://download.opensuse.org/update/leap/${OS_VERSION_ID}/oss/" 99 || true
    add_repo_if_missing "repo-update-non-oss" "openSUSE-Leap-Update-Non-Oss" "https://download.opensuse.org/update/leap/${OS_VERSION_ID}/non-oss/" 99 || true
  fi

  zypper_refresh
}

setup_packman() {
  section "Add Packman and switch codecs to Packman"

  local packman_url=""
  if [[ "$OS_ID" == "opensuse-tumbleweed" ]]; then
    packman_url="https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/"
  else
    if [[ -z "${OS_VERSION_ID:-}" ]]; then
      warn "VERSION_ID is empty, skipping Packman setup"
      return 0
    fi
    packman_url="https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Leap_${OS_VERSION_ID}/"
  fi

  add_repo_if_missing "packman" "Packman Repository" "$packman_url" 90 || true
  zypper_refresh

  if [[ "$OS_ID" == "opensuse-tumbleweed" ]]; then
    section "Vendor switch to Packman (Tumbleweed)"
    zypper -n dup --from packman --allow-vendor-change || warn "Packman vendor switch failed (continuing)"
  else
    info "Leap detected: will allow vendor changes during multimedia installs"
  fi
}

printf "${BOLD}${GREEN}openSUSE Tumbleweed KDE Bootstrap${RESET}\n"
require_root

TARGET_USER="$(get_target_user)"
info "Target user: ${TARGET_USER}"

detect_opensuse

# -----------------------------
# Refresh repos (no full system update)
# -----------------------------
section "Refresh repos (no system update)"
setup_official_repos

# -----------------------------
# Base tools
# -----------------------------
section "Base tools"
try_install curl wget git fastfetch btop htop python3 python3-pip flatpak distrobox vlc

# -----------------------------
# Packman + Multimedia
# -----------------------------
setup_packman

section "Multimedia (FFmpeg + GStreamer)"
if [[ "$OS_ID" == "opensuse-leap" ]]; then
  section "Installing: ffmpeg (allow vendor change)"
  zypper -n in -y --allow-vendor-change ffmpeg || warn "Could not install: ffmpeg (skipping)"
else
  try_install ffmpeg
fi

try_install \
  gstreamer \
  gstreamer-plugins-base \
  gstreamer-plugins-good \
  gstreamer-plugins-bad \
  gstreamer-plugins-ugly \
  gstreamer-plugins-libav

# -----------------------------
# KDE Plasma + SDDM
# -----------------------------
section "KDE Plasma and SDDM"

section "Installing pattern: kde_plasma"
if zypper -n in -y -t pattern kde_plasma; then
  info "Installed pattern: kde_plasma"
else
  warn "Pattern kde_plasma not available, installing core KDE packages instead"
  try_install sddm konsole spectacle ark okular gwenview discover discover6
fi

try_install \
  discover6

# -----------------------------
# Gaming tools
# -----------------------------
section "Gaming tools"
try_install steam lutris mangohud obs-studio

# -----------------------------
# Other Software
# -----------------------------
section "Gaming tools"
try_install keepassxc qbittorrent kdelive pinta kcalc okular gwenview kolourpaint libglvnd-gles kate kcolorchooser

# -----------------------------
# Flatpak apps
# -----------------------------
section "Flatpak apps"

if ! have_cmd flatpak; then
  warn "flatpak command not found (skipping Flatpak section)"
else
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

  section "Flatpak: Flatseal"
  flatpak install -y flathub com.github.tchx84.Flatseal || true

  section "Flatpak: ProtonUp-Qt"
  flatpak install -y flathub net.davidotek.pupgui2 || true

  section "Flatpak: ProtonPlus"
  flatpak install -y flathub com.vysp3r.ProtonPlus || true

  section "Flatpak: Heroic"
  flatpak install -y flathub com.heroicgameslauncher.hgl || true

  section "Flatpak: FreeFileSync"
  flatpak install -y flathub org.freefilesync.FreeFileSync || true

  section "Flatpak: LocalSend"
  flatpak install -y flathub org.localsend.localsend_app || true

  section "Flatpak: Vesktop"
  flatpak install -y flathub dev.vencord.Vesktop || true

  section "Flatpak: Waterfox"
  flatpak install -y flathub net.waterfox.waterfox || true
fi

# -----------------------------
# Virtualization
# -----------------------------
section "Virtualization"
try_install virt-manager qemu qemu-kvm libvirt libvirt-client virt-install virt-viewer ovmf swtpm

systemctl enable --now libvirtd || true
usermod -aG libvirt "${TARGET_USER}" 2>/dev/null || true
usermod -aG kvm "${TARGET_USER}" 2>/dev/null || true

############################################################
# KDE CONNECT FIREWALL
# Allows KDE Connect through Fedora's public firewalld zone.
############################################################
firewall-cmd --permanent --zone=home --add-service=kdeconnect
firewall-cmd --reload

############################################################
# LOCALSEND FIREWALL
# Allows LocalSend through firewalld.
############################################################
sudo firewall-cmd --permanent --zone=public --add-port=53317/tcp
sudo firewall-cmd --permanent --zone=public --add-port=53317/udp
sudo firewall-cmd --reload

############################################################
# LIBVIRT FIREWALL
# Allows LibVirt through firewalld.
############################################################
firewall-cmd --zone=libvirt --add-port=53317/tcp --permanent
firewall-cmd --zone=libvirt --add-port=53317/udp --permanent
firewall-cmd --reload

# -----------------------------
# Boot target
# -----------------------------
section "Boot configuration"

systemctl set-default graphical.target || true
echo 'DISPLAYMANAGER="sddm"' > /etc/sysconfig/displaymanager
systemctl enable display-manager.service || true

# -----------------------------
# Finish
# -----------------------------
section "Complete"
info "Bootstrap finished"
info "Reboot to start KDE Plasma:"
cmdhint "reboot"
