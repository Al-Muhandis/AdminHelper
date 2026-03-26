#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
VER_MAJOR="0"
VER_MINOR=$(grep -oP '<MinorVersionNr Value="\K[^"]+' src/adminhelperd.lpi)
VER_REV=$(grep -oP '<RevisionNr Value="\K[^"]+' src/adminhelperd.lpi)
VER_BUILD=$(grep -oP '<BuildNr Value="\K[^"]+' src/adminhelperd.lpi)

export app_VER="${VER_MAJOR}.${VER_MINOR}.${VER_REV}"
export app_VERdeb="${VER_BUILD}"

MAINTAINER_NAME="Renat Suleymanov"
MAINTAINER_EMAIL="mail@Renat.Su"
PACKAGE_NAME="tgadmin"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build always happens in Linux fs to avoid NTFS chmod issues in WSL
BUILD_DIR="/tmp/${PACKAGE_NAME}_build"

STAGING_DIR="${BUILD_DIR}/debian"
DEB_NAME="${PACKAGE_NAME}_${app_VER}-${app_VERdeb}_amd64.deb"
OUTPUT_DEB="${BUILD_DIR}/${DEB_NAME}"

# ---------------------------------------------------------------------------
# Detect WSL
# ---------------------------------------------------------------------------
detect_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null || \
    grep -qi wsl /proc/version 2>/dev/null
}

# Where to copy the finished .deb.
# Set via env: WINDOWS_OUTPUT_DIR="/mnt/c/Users/..." ./build-deb.sh
if [ -n "${WINDOWS_OUTPUT_DIR:-}" ]; then
    COPY_TARGET="${WINDOWS_OUTPUT_DIR}"
else
    COPY_TARGET="${SCRIPT_DIR}"
fi

# ---------------------------------------------------------------------------
# Dependencies' checking
# ---------------------------------------------------------------------------
check_deps() {
    local missing=()
    for cmd in dpkg-deb gzip du awk grep jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: missing required tools: ${missing[*]}" >&2
        echo "Install with: sudo apt-get install dpkg-dev gzip jq" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Validate tgadmin.json before building
# ---------------------------------------------------------------------------
validate_config() {
    local config="${SCRIPT_DIR}/src/tgadmin.json"
    if [ ! -f "${config}" ]; then
        echo "ERROR: src/tgadmin.json not found" >&2
        exit 1
    fi
    if ! jq empty "${config}" 2>/dev/null; then
        echo "ERROR: src/tgadmin.json is not valid JSON" >&2
        exit 1
    fi
}

validate_binary() {
    local binary="${SCRIPT_DIR}/debian/usr/bin/tgadmin"
    if [ ! -x "${binary}" ]; then
        echo "ERROR: ${binary} is missing or not executable" >&2
        echo "Build the daemon and place it at debian/usr/bin/tgadmin before packaging." >&2
        exit 1
    fi
}

normalize_maintainer_scripts() {
    local script
    for script in "${STAGING_DIR}/DEBIAN/postinst" "${STAGING_DIR}/DEBIAN/postrm"; do
        if [ -f "${script}" ]; then
            sed -i 's/\r$//' "${script}"
        fi
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
check_deps
validate_config
validate_binary

echo "==> Building ${PACKAGE_NAME} v${app_VER}-${app_VERdeb}"
echo "==> Build dir (Linux fs): ${BUILD_DIR}"

# Recreate build-dir in /tmp from scratch
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Copy staging from sources in /tmp — here chmod works correctly
cp -r "${SCRIPT_DIR}/debian" "${STAGING_DIR}"
normalize_maintainer_scripts

# Include db_schema.sql — used by postinst to initialize the database
mkdir -p "${STAGING_DIR}/usr/share/${PACKAGE_NAME}"
cp "${SCRIPT_DIR}/src/db_schema.sql" "${STAGING_DIR}/usr/share/${PACKAGE_NAME}/db_schema.sql"

# Include tgadmin.json as default config
# postinst will fill in DB credentials automatically
mkdir -p "${STAGING_DIR}/etc/${PACKAGE_NAME}"
cp "${SCRIPT_DIR}/src/tgadmin.json" "${STAGING_DIR}/etc/${PACKAGE_NAME}/tgadmin.json"

# Set permissions
find "${STAGING_DIR}" -type d -exec chmod 0755 {} \;
find "${STAGING_DIR}" -type f -exec chmod 0644 {} \;
find "${STAGING_DIR}/usr/bin" -type f -exec chmod 0755 {} \;

# Maintainer scripts must be executable
chmod 0755 "${STAGING_DIR}/DEBIAN/postinst"
chmod 0755 "${STAGING_DIR}/DEBIAN/postrm"

# Config file should not be world-readable (contains credentials after install)
chmod 0640 "${STAGING_DIR}/etc/${PACKAGE_NAME}/tgadmin.json"

# Version and size in control
echo "Version: ${app_VER}.0-${app_VERdeb}" >> "${STAGING_DIR}/DEBIAN/control"
SIZE_IN_KB="$(du -s "${STAGING_DIR}" | awk '{print $1}')"
echo "Installed-Size: ${SIZE_IN_KB}" >> "${STAGING_DIR}/DEBIAN/control"

# Changelog
CHANGELOG="${STAGING_DIR}/usr/share/doc/${PACKAGE_NAME}/changelog.Debian"
DATE=$(date -R)
{
    echo "${PACKAGE_NAME} (${app_VER}-${app_VERdeb}) unstable; urgency=medium"
    echo ""
    echo "  * fixes"
    echo ""
    echo " -- ${MAINTAINER_NAME} <${MAINTAINER_EMAIL}>  ${DATE}"
} >> "${CHANGELOG}"
gzip -9 -n "${CHANGELOG}"

# Package building
dpkg-deb --root-owner-group --build "${STAGING_DIR}" "${OUTPUT_DEB}"

echo "==> Package built: ${OUTPUT_DEB}"

# Copy ready .DEB to needed place
mkdir -p "${COPY_TARGET}"
cp "${OUTPUT_DEB}" "${COPY_TARGET}/"
echo "==> Copied to: ${COPY_TARGET}/${DEB_NAME}"

echo "==> Done."
