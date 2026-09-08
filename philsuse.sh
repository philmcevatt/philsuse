#!/usr/bin/env bash
set -euo pipefail

# philsuse.sh
#
# Purpose:
# To go from an openSUSE Tumbleweed minimal / server-style install...
# Add KDE Plasma, selected native packages, Packman and Flatpaks
# ... to end up with my normal openSUSE KDE desktop.

############################################################
# VERSION
############################################################
PHILSUSE_VERSION="0.2.0"

############################################################
# TOGGLES
############################################################
INSTALL_PACKMAN=true
# Adds Packman and performs the Tumbleweed vendor switch for multimedia codecs.
INSTALL_VIRT=true
# Installs Virt-Manager, libvirt, QEMU/KVM, OVMF and TPM support.

############################################################
# INITIAL SAFETY CHECKS
# Ensures script is run through sudo from a normal user.
# Also verifies that the target OS is openSUSE Tumbleweed.
############################################################
if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run with sudo:"
  echo "  sudo ./philsuse.sh"
  exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
  echo "Could not detect the normal user account."
  echo "Do not run this from a root shell or with su."
  echo "Run it from your normal account with:"
  echo "  sudo ./philsuse.sh"
  exit 1
fi

if ! id "${TARGET_USER}" &>/dev/null; then
  echo "Detected user '${TARGET_USER}' does not exist."
  exit 1
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
  echo "Could not determine the home directory for '${TARGET_USER}'."
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Could not read /etc/os-release."
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "opensuse-tumbleweed" ]]; then
  echo "This script is intended for openSUSE Tumbleweed only."
  echo "Detected: ${PRETTY_NAME:-unknown Linux distribution}"
  exit 1
fi

OPENSUSE_NAME="${PRETTY_NAME:-openSUSE Tumbleweed}"
OPENSUSE_VERSION="${VERSION_ID:-Tumbleweed}"

############################################################
# LOGGING
# Creates a full log and a final review summary on the
# target user's Desktop.
############################################################
LOG_DIRECTORY="${TARGET_HOME}/Desktop"
LOG_TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
LOGFILE="${LOG_DIRECTORY}/philsuse-${PHILSUSE_VERSION}-${LOG_TIMESTAMP}.log"
SUMMARY_FILE="${LOG_DIRECTORY}/philsuse-summary-${PHILSUSE_VERSION}-${LOG_TIMESTAMP}.txt"

mkdir -p "${LOG_DIRECTORY}"
chown "${TARGET_USER}:${TARGET_USER}" "${LOG_DIRECTORY}"
chmod 755 "${LOG_DIRECTORY}"

touch "${LOGFILE}" "${SUMMARY_FILE}"
chown "${TARGET_USER}:${TARGET_USER}" "${LOGFILE}" "${SUMMARY_FILE}"
chmod 644 "${LOGFILE}" "${SUMMARY_FILE}"

exec > >(tee -a "${LOGFILE}")
exec 2>&1

############################################################
# COLOURS AND HELPERS
# Logging and feedback colours and helpers.
############################################################
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

declare -a COMPLETED_SECTIONS=()
declare -a WARNINGS=()
declare -a NOTES=()
declare -a SKIPPED_SECTIONS=()

section() {
  echo -e "\n${GREEN}==> $1${RESET}"
}

complete_section() {
  COMPLETED_SECTIONS+=("$1")
}

warn() {
  local message="$1"
  echo -e "${YELLOW}Warning:${RESET} ${message}"
  WARNINGS+=("${message}")
}

note() {
  local message="$1"
  echo -e "${BLUE}Note:${RESET} ${message}"
  NOTES+=("${message}")
}

skip_section() {
  local message="$1"
  echo "Skipped: ${message}"
  SKIPPED_SECTIONS+=("${message}")
}

############################################################
# ENVIRONMENT
############################################################
section "Environment"
echo "PhilSUSE Version: ${PHILSUSE_VERSION}"
echo "openSUSE: ${OPENSUSE_NAME}"
echo "Version ID: ${OPENSUSE_VERSION}"
echo "Target User: ${TARGET_USER}"
echo "Installation Log: ${LOGFILE}"
echo "Install Packman: ${INSTALL_PACKMAN}"
echo "Install Virt: ${INSTALL_VIRT}"
complete_section "Environment"

############################################################
# REFRESH EXISTING REPOSITORIES
# The installer already creates the official openSUSE repos.
# Do not add or recreate them here.
############################################################
section "Refresh existing repositories"
if zypper -n --gpg-auto-import-keys refresh; then
  complete_section "Refresh existing repositories"
else
  warn "Repository refresh reported an issue. Review the configured repositories before continuing."
fi

############################################################
# KDE FOUNDATION: PLASMA PATTERN
# Installs the openSUSE KDE Plasma desktop pattern.
############################################################
section "KDE Foundation: Plasma pattern"

if zypper -n install -y -t pattern kde_plasma; then
  complete_section "KDE Foundation: Plasma pattern"
else
  warn "The kde_plasma pattern could not be installed. Review the log before continuing."
fi

############################################################
# KDE FOUNDATION: CURATED PACKAGES
# KDE applications and desktop components I want explicitly
# installed regardless of what the Plasma pattern contains.
############################################################
section "KDE Foundation: Curated Packages"

KDE_CURATED_PACKAGES=(
  ark
  discover6
  gwenview
  kate
  kcalc
  kdeconnect-kde
  kcolorchooser
  kolourpaint
  konsole
  libglvnd
  okular
  spectacle
)

if zypper -n install -y "${KDE_CURATED_PACKAGES[@]}"; then
  complete_section "KDE Foundation: Curated Packages"
else
  warn "One or more KDE Foundation: Curated Packages could not be installed."
fi

############################################################
# GRAPHICAL DISPLAY SUPPORT
# Explicitly installs X11 and XWayland support required by
# the Plasma/SDDM desktop setup.
############################################################
section "Graphical display support"

GRAPHICAL_DISPLAY_READY=true

if zypper -n install -y \
  xorg-x11-server \
  xwayland; then

  complete_section "Graphical display support"
else
  warn "X11/XWayland display support could not be fully installed."
  GRAPHICAL_DISPLAY_READY=false
fi

############################################################
# SDDM AND GRAPHICAL BOOT
# Only enables graphical boot when X11/XWayland was
# successfully installed above.
############################################################
if [[ "${GRAPHICAL_DISPLAY_READY}" == "true" ]]; then
  section "Enable SDDM and graphical boot"

  GRAPHICAL_BOOT_READY=true

  if ! systemctl enable --force sddm.service; then
    warn "Failed to enable sddm.service."
    GRAPHICAL_BOOT_READY=false
  fi

  if [[ "${GRAPHICAL_BOOT_READY}" == "true" ]]; then
    if systemctl set-default graphical.target; then
      echo "Default boot target set to graphical.target."
      complete_section "Enable SDDM and graphical boot"
    else
      warn "Could not set graphical.target as the default boot target."
    fi
  fi
else
  warn "Graphical boot was not enabled because X11/XWayland installation failed."
fi

# Deliberately do not restart SDDM here. This script is designed to
# finish cleanly in the TTY and start the graphical login on reboot.

############################################################
# SYSTEM MANAGEMENT TOOLS
############################################################
section "System management tools"
SYSTEM_MANAGEMENT_PACKAGES=(
  myrlyn
  opi
  patterns-cockpit
  patterns-cockpit-client
)
if zypper -n install -y "${SYSTEM_MANAGEMENT_PACKAGES[@]}"; then
  complete_section "System management tools"
else
  warn "One or more System management tools could not be installed."
fi

############################################################
# BASE & SYSTEM UTILITIES
############################################################
section "Core & System utilities"
CORE_PACKAGES=(
  curl
  wget
  git
  fastfetch
  fish
  btop
  python3
  python3-pip
  flatpak
  distrobox
)
if zypper -n install -y "${CORE_PACKAGES[@]}"; then
  complete_section "Core & System utilities"
else
  warn "One or more Core & System utility packages could not be installed."
fi

############################################################
# PRINTING
# Installs the printing stack and HP printer support.
# Some packages may already be present through the Plasma
# pattern, but are explicitly installed here so printing does
# not depend on the current contents of another pattern.
############################################################
section "Printing"

PRINTING_PACKAGES=(
  cups
  cups-filters
  ghostscript
  nss-mdns
  gutenprint
  hplip
)

if zypper -n install -y "${PRINTING_PACKAGES[@]}"; then
  complete_section "Printing"
else
  warn "One or more printing packages could not be installed."
fi

############################################################
# ENABLE PRINTING SERVICE
############################################################
section "Enable printing service"

if systemctl enable --now cups.service; then
  complete_section "Enable printing service"
else
  warn "CUPS could not be enabled or started."
fi

############################################################
# PACKMAN
# Keep Packman separate from the installer-created official
# repositories. Adds it only when no Packman repo is present.
############################################################
if [[ "${INSTALL_PACKMAN}" == "true" ]]; then
  section "Packman repository"
  PACKMAN_READY=true
  PACKMAN_URL="https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/"

  PACKMAN_ALIAS="$(zypper lr -u 2>/dev/null | awk -F'|' 'tolower($0) ~ /packman/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')"

  if [[ -n "${PACKMAN_ALIAS}" ]]; then
    echo "A Packman repository is already configured: ${PACKMAN_ALIAS}"
  elif zypper -n ar -f -p 90 -n "Packman Repository" "${PACKMAN_URL}" packman; then
    PACKMAN_ALIAS="packman"
    echo "Packman repository added."
  else
    warn "Packman repository could not be added."
    PACKMAN_READY=false
  fi

  if [[ "${PACKMAN_READY}" == "true" ]]; then
    if ! zypper -n --gpg-auto-import-keys refresh; then
      warn "Repository refresh failed after configuring Packman."
      PACKMAN_READY=false
    fi
  fi

  if [[ "${PACKMAN_READY}" == "true" ]]; then
    section "Packman vendor switch"
    if zypper -n dup --from "${PACKMAN_ALIAS}" --allow-vendor-change; then
      complete_section "Packman repository and vendor switch"
    else
      warn "Packman vendor switch failed."
    fi
  fi
else
  skip_section "Packman repository and vendor switch"
fi

############################################################
# MULTIMEDIA CODECS
############################################################
section "Multimedia and codecs"
MULTIMEDIA_READY=true

if ! zypper -n install -y ffmpeg; then
  warn "FFmpeg could not be installed."
  MULTIMEDIA_READY=false
fi

MULTIMEDIA_PACKAGES=(
  gstreamer
  gstreamer-plugins-base
  gstreamer-plugins-good
  gstreamer-plugins-bad
  gstreamer-plugins-ugly
  gstreamer-plugins-libav
)
if ! zypper -n install -y "${MULTIMEDIA_PACKAGES[@]}"; then
  warn "One or more GStreamer codec packages could not be installed."
  MULTIMEDIA_READY=false
fi

if [[ "${MULTIMEDIA_READY}" == "true" ]]; then
  complete_section "Multimedia and codecs"
fi

############################################################
# WEB AND INTERNET
############################################################
section "Web and internet"
WEB_PACKAGES=(
  keepassxc
  qbittorrent
)
if zypper -n install -y "${WEB_PACKAGES[@]}"; then
  complete_section "Web and internet"
else
  warn "One or more Web and internet packages could not be installed."
fi

############################################################
# CONTENT CREATION
# Kdenlive is installed as a Flatpak later.
############################################################
section "Content creation"
CONTENT_PACKAGES=(
  obs-studio
  pinta
)
if zypper -n install -y "${CONTENT_PACKAGES[@]}"; then
  complete_section "Content creation"
else
  warn "One or more Content creation packages could not be installed."
fi

############################################################
# OFFICE
# LibreOffice Writer and Calc only.
# --no-recommends prevents the rest of the LibreOffice suite
# being pulled in automatically.
# libreoffice-qt6 provides proper Plasma/Qt6 integration.
############################################################
section "Office"

OFFICE_PACKAGES=(
  libreoffice-writer
  libreoffice-calc
  libreoffice-l10n-en
  libreoffice-l10n-en_GB
  libreoffice-qt6
)

if zypper -n install -y --no-recommends "${OFFICE_PACKAGES[@]}"; then
  complete_section "Office"
else
  warn "One or more Office packages could not be installed."
fi

############################################################
# GAME LAUNCHERS
# Steam & Lutris. Heroic added later as a Flatpak.
############################################################
section "Game Launchers"

GAME_LAUNCHERS=(
  steam
  lutris
)
if zypper -n install -y "${GAME_LAUNCHERS[@]}"; then
  complete_section "Game Launchers"
else
  warn "One or more Game Launchers could not be installed."
fi

############################################################
# GAMING EXTRAS
# Gaming performance, compatibility and monitoring tools.
############################################################
section "Gaming Extras"
GAMING_EXTRAS=(
  gamemode
  gamescope
  goverlay
  mangohud
  protontricks
  winetricks
)
if zypper -n install -y "${GAMING_EXTRAS[@]}"; then
  complete_section "Gaming Extras"
else
  warn "One or more Gaming Extras could not be installed."
fi

############################################################
# VIRTUALISATION
# Virt-Manager, libvirt, QEMU/KVM, OVMF and TPM support.
############################################################
if [[ "${INSTALL_VIRT}" == "true" ]]; then
  section "Virtualisation stack"
  VIRTUALISATION_READY=true

  VIRT_PACKAGES=(
    virt-manager
    qemu
    qemu-kvm
    libvirt
    libvirt-client
    virt-install
    virt-viewer
    ovmf
    swtpm
  )

  if ! zypper -n install -y "${VIRT_PACKAGES[@]}"; then
    warn "Virtualisation packages could not be installed completely."
    VIRTUALISATION_READY=false
  fi

  if [[ "${VIRTUALISATION_READY}" == "true" ]]; then
    if systemctl enable --now libvirtd; then
      echo "libvirtd enabled and started."
    else
      warn "Virtualisation packages installed, but libvirtd could not be enabled."
      VIRTUALISATION_READY=false
    fi
  fi

  if [[ "${VIRTUALISATION_READY}" == "true" ]]; then
    if usermod -aG libvirt,kvm "${TARGET_USER}"; then
      echo "${TARGET_USER} added to the libvirt and kvm groups."
      complete_section "Virtualisation stack"
    else
      warn "Virtualisation installed, but ${TARGET_USER} could not be added to the libvirt/kvm groups."
    fi
  fi
else
  skip_section "Virtualisation stack"
fi

############################################################
# FLATPAK AND FLATHUB
# Discover integration plus Flathub registration.
############################################################
section "Flatpak and Flathub"
FLATPAK_READY=true

if ! zypper -n install -y flatpak; then
  warn "Flatpak could not be installed."
  FLATPAK_READY=false
fi

# Plasma Discover's Flatpak backend may already be pulled in by
# Discover/the Plasma pattern; request it explicitly when available.
if ! zypper -n install -y discover6-backend-flatpak; then
  note "discover6-backend-flatpak could not be installed explicitly. Discover will still be installed, but Flatpak integration inside Discover may be unavailable."
fi

if [[ "${FLATPAK_READY}" == "true" ]]; then
  if flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
    complete_section "Flatpak and Flathub"
  else
    warn "Flathub could not be registered."
    FLATPAK_READY=false
  fi
fi

############################################################
# FLATPAK APPS
# Kept aligned with the PhilFed Flatpak application set.
############################################################
if [[ "${FLATPAK_READY}" == "true" ]]; then
  section "Flatpak apps"
  flatpak install -y flathub com.github.tchx84.Flatseal || warn "Flatseal Flatpak failed"
  flatpak install -y flathub com.usebottles.bottles || warn "Bottles Flatpak failed"
  flatpak install -y flathub org.mozilla.firefox || warn "Firefox Flatpak failed"
  flatpak install -y flathub one.ablaze.floorp || warn "Floorp Flatpak failed"
  flatpak install -y flathub org.freefilesync.FreeFileSync || warn "FreeFileSync Flatpak failed"
  flatpak install -y flathub com.heroicgameslauncher.hgl || warn "Heroic Flatpak failed"
  flatpak install -y flathub org.kde.kdenlive || warn "Kdenlive Flatpak failed"
  flatpak install -y flathub org.localsend.localsend_app || warn "LocalSend Flatpak failed"
  flatpak install -y flathub md.obsidian.Obsidian || warn "Obsidian Flatpak failed"
  flatpak install -y flathub com.vysp3r.ProtonPlus || warn "ProtonPlus Flatpak failed"
  flatpak install -y flathub dev.vencord.Vesktop || warn "Vesktop Flatpak failed"
  flatpak install -y flathub com.vivaldi.Vivaldi || warn "Vivaldi Flatpak failed"
  flatpak install -y flathub org.videolan.VLC || warn "VLC Flatpak failed"
  flatpak install -y flathub net.waterfox.waterfox || warn "Waterfox Flatpak failed"

  if flatpak update -y; then
    echo "Flatpak applications and runtimes updated."
  else
    warn "Flatpak application or runtime update failed."
  fi

  complete_section "Flatpak apps"
else
  skip_section "Flatpak apps"
fi

############################################################
# KDE CONNECT FIREWALL
############################################################
section "KDE Connect firewall"
KDECONNECT_FIREWALL_READY=true

if ! firewall-cmd --permanent --zone=public --add-service=kdeconnect; then
  warn "Failed to enable KDE Connect firewall service."
  KDECONNECT_FIREWALL_READY=false
fi

if ! firewall-cmd --reload; then
  warn "Failed to reload firewall."
  KDECONNECT_FIREWALL_READY=false
fi

if [[ "${KDECONNECT_FIREWALL_READY}" == "true" ]]; then
  complete_section "KDE Connect firewall"
fi

############################################################
# LOCALSEND FIREWALL
############################################################
section "LocalSend firewall"
LOCALSEND_FIREWALL_READY=true

if ! firewall-cmd --add-port=53317/tcp --permanent; then
  warn "Failed to open LocalSend TCP port (public zone)."
  LOCALSEND_FIREWALL_READY=false
fi

if ! firewall-cmd --add-port=53317/udp --permanent; then
  warn "Failed to open LocalSend UDP port (public zone)."
  LOCALSEND_FIREWALL_READY=false
fi

if firewall-cmd --get-zones | grep -qw libvirt; then
  if ! firewall-cmd --zone=libvirt --add-port=53317/tcp --permanent; then
    warn "Failed to open LocalSend TCP port (libvirt zone)."
    LOCALSEND_FIREWALL_READY=false
  fi

  if ! firewall-cmd --zone=libvirt --add-port=53317/udp --permanent; then
    warn "Failed to open LocalSend UDP port (libvirt zone)."
    LOCALSEND_FIREWALL_READY=false
  fi
else
  note "libvirt firewalld zone not present, skipping VM guest access for LocalSend."
fi

if ! firewall-cmd --reload; then
  warn "Failed to reload firewall."
  LOCALSEND_FIREWALL_READY=false
fi

if [[ "${LOCALSEND_FIREWALL_READY}" == "true" ]]; then
  complete_section "LocalSend firewall"
fi

############################################################
# KONSOLE / BASH BRACKETED PASTE
# Prevents pasted multi-line commands from being submitted
# automatically in Bash/Readline.
############################################################
section "Enable Bash bracketed paste"

INPUTRC="${TARGET_HOME}/.inputrc"

if grep -qxF 'set enable-bracketed-paste on' "${INPUTRC}" 2>/dev/null; then
  echo "Bash bracketed paste is already enabled for ${TARGET_USER}."
  complete_section "Enable Bash bracketed paste"
else
  if printf '%s\n' 'set enable-bracketed-paste on' >> "${INPUTRC}"; then
    if chown "${TARGET_USER}:${TARGET_USER}" "${INPUTRC}"; then
      echo "Bash bracketed paste enabled for ${TARGET_USER}."
      complete_section "Enable Bash bracketed paste"
    else
      warn "Bracketed paste was configured, but ownership of ${INPUTRC} could not be corrected."
    fi
  else
    warn "Could not configure Bash bracketed paste for ${TARGET_USER}."
  fi
fi

############################################################
# USER SHELL
# Sets Fish as the default shell for the normal user and
# creates standard Zypper and Flatpak aliases.
############################################################
section "Set Fish as shell for ${TARGET_USER}"

FISH_READY=true

if [[ -x /usr/bin/fish ]]; then
  if chsh -s /usr/bin/fish "${TARGET_USER}"; then
    complete_section "Fish default shell"
  else
    warn "Could not set Fish shell for ${TARGET_USER}"
    FISH_READY=false
  fi

  if [[ "${FISH_READY}" == "true" ]]; then
    section "Configure Fish aliases"

    if sudo -u "${TARGET_USER}" fish -c "
      alias --save zin='sudo zypper install'
      alias --save zre='sudo zypper remove'
      alias --save zse='zypper search'
      alias --save zup='sudo zypper dup'
      alias --save zclean='sudo zypper clean all'
      alias --save zlist='zypper search --installed-only'
      alias --save zinfo='zypper info'

      alias --save fp='flatpak'
      alias --save fpi='flatpak install'
      alias --save fpr='flatpak uninstall'
      alias --save fps='flatpak search'
      alias --save fpu='flatpak update'
    "; then
      complete_section "Fish aliases"
    else
      warn "Could not configure Fish aliases for ${TARGET_USER}"
    fi
  fi
else
  warn "Fish is not installed. Skipping shell configuration."
fi

############################################################
# FISH STARTUP
# Removes the default Fish greeting and runs Fastfetch when
# starting an interactive Fish shell.
############################################################
section "Configure Fish startup"

FISH_CONFIG_DIR="${TARGET_HOME}/.config/fish"
FISH_CONF_DIR="${FISH_CONFIG_DIR}/conf.d"
FASTFETCH_CONF="${FISH_CONF_DIR}/fastfetch.fish"

FISH_STARTUP_READY=true

# Set an empty universal greeting so Fish does not display
# its default welcome message.
if ! sudo -u "${TARGET_USER}" fish -c 'set -U fish_greeting'; then
  warn "Could not disable the default Fish greeting."
  FISH_STARTUP_READY=false
fi

# Ensure the user's Fish conf.d directory exists.
if ! install -d \
  -o "${TARGET_USER}" \
  -g "${TARGET_USER}" \
  "${FISH_CONF_DIR}"; then

  warn "Could not create the Fish conf.d directory."
  FISH_STARTUP_READY=false
fi

# Create a modular Fastfetch startup file rather than editing
# config.fish directly.
if [[ "${FISH_STARTUP_READY}" == "true" ]]; then
  if cat > "${FASTFETCH_CONF}" <<'EOF'
if status is-interactive
    fastfetch
end
EOF
  then
    if chown "${TARGET_USER}:${TARGET_USER}" "${FASTFETCH_CONF}"; then
      complete_section "Fish startup"
    else
      warn "Fastfetch startup file was created, but its ownership could not be corrected."
    fi
  else
    warn "Could not create the Fastfetch Fish startup file."
  fi
fi

############################################################
# ZYPPER CACHE CLEANUP
############################################################
section "Zypper cache cleanup"
if zypper clean --all; then
  echo "Zypper caches cleared."
  complete_section "Zypper cache cleanup"
else
  warn "Zypper cache cleanup failed."
fi

############################################################
# INSTALLATION SUMMARY
# Printed to the TTY and written to the Desktop summary file.
############################################################
section "Installation summary"
{
  echo
  echo "============================================================"
  echo
  echo "PhilSUSE ${PHILSUSE_VERSION} installation complete."
  echo
  echo "Installed:"

  if (( ${#COMPLETED_SECTIONS[@]} == 0 )); then
    echo "  None recorded."
  else
    for completed_section in "${COMPLETED_SECTIONS[@]}"; do
      echo "  ✓ ${completed_section}"
    done
  fi

  echo
  echo "Skipped:"

  if (( ${#SKIPPED_SECTIONS[@]} == 0 )); then
    echo "  None"
  else
    for skipped_section in "${SKIPPED_SECTIONS[@]}"; do
      echo "  – ${skipped_section}"
    done
  fi

  echo
  echo "Warnings:"

  if (( ${#WARNINGS[@]} == 0 )); then
    echo "  None"
  else
    for warning_message in "${WARNINGS[@]}"; do
      echo "  • ${warning_message}"
    done
  fi

  echo
  echo "Notes:"

  if (( ${#NOTES[@]} == 0 )); then
    echo "  None"
  else
    for note_message in "${NOTES[@]}"; do
      echo "  • ${note_message}"
    done
  fi

  echo
  echo "Installation log:"
  echo "  ${LOGFILE}"
  echo
  echo "Reboot when ready:"
  echo
  echo "    sudo reboot"
  echo
  echo "------------------------------------------------------------"
  echo
  echo "No chameleons were harmed during this installation."
  echo
  echo "============================================================"
} | tee -a "${SUMMARY_FILE}"
