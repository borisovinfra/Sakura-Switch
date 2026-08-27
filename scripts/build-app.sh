#!/bin/bash
set -euo pipefail

# Build Sakura Switch.app — native macOS application

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Sakura Switch"
EXECUTABLE_NAME="SakuraSwitch"
ICON_NAME="SakuraSwitch.icns"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/build/${APP_NAME}.app"
TARGET_APP="/Applications/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
HELPERS_DIR="${CONTENTS_DIR}/Helpers"
HELPER_SOURCE="$ROOT_DIR/Resources/Helper/sakuraswitch-mtp-helper.c"
HELPER_BINARY="${HELPERS_DIR}/sakuraswitch-mtp-helper"
ICON_SOURCE="$ROOT_DIR/Assets/${ICON_NAME}"
INSTALL_TO_APPLICATIONS=false
APP_VERSION="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || printf "dev")"

for arg in "$@"; do
    case "$arg" in
        --install)
            INSTALL_TO_APPLICATIONS=true
            ;;
        --version=*)
            APP_VERSION="${arg#*=}"
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: scripts/build-app.sh [--install] [--version=x.y.z]"
            exit 1
            ;;
    esac
done

echo "Building ${APP_NAME} (release)..."
unset DEVELOPER_DIR 2>/dev/null || true
swift build --package-path "$ROOT_DIR" -c release --quiet

echo "Creating app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}" "${HELPERS_DIR}"

# Copy executable
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
chmod +x "${MACOS_DIR}/${EXECUTABLE_NAME}"

# Build bundled privileged MTP helper.
if [[ ! -f "${HELPER_SOURCE}" ]]; then
    echo "❌ MTP helper source not found: ${HELPER_SOURCE}"
    exit 1
fi

echo "Building bundled MTP helper..."

cc -O2 \
    "${HELPER_SOURCE}" \
    -o "${HELPER_BINARY}" \
    $(pkg-config --cflags --libs libmtp libusb-1.0)

chmod 755 "${HELPER_BINARY}"

# Bundle libmtp + libusb inside the application.
# Homebrew is required only on the machine that builds Sakura Switch.
if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrew is required on the build machine."
    exit 1
fi

LIBMTP_PREFIX="$(brew --prefix libmtp)"
LIBUSB_PREFIX="$(brew --prefix libusb)"

LIBMTP_SOURCE="${LIBMTP_PREFIX}/lib/libmtp.9.dylib"
LIBUSB_SOURCE="${LIBUSB_PREFIX}/lib/libusb-1.0.0.dylib"

LIBMTP_BUNDLED="${FRAMEWORKS_DIR}/libmtp.9.dylib"
LIBUSB_BUNDLED="${FRAMEWORKS_DIR}/libusb-1.0.0.dylib"

if [[ ! -f "${LIBMTP_SOURCE}" ]]; then
    echo "❌ libmtp not found: ${LIBMTP_SOURCE}"
    exit 1
fi

if [[ ! -f "${LIBUSB_SOURCE}" ]]; then
    echo "❌ libusb not found: ${LIBUSB_SOURCE}"
    exit 1
fi

cp "${LIBMTP_SOURCE}" "${LIBMTP_BUNDLED}"
cp "${LIBUSB_SOURCE}" "${LIBUSB_BUNDLED}"

chmod 755 "${LIBMTP_BUNDLED}" "${LIBUSB_BUNDLED}"

# Make bundled libraries relocatable.
install_name_tool \
    -id "@rpath/libmtp.9.dylib" \
    "${LIBMTP_BUNDLED}"

install_name_tool \
    -id "@rpath/libusb-1.0.0.dylib" \
    "${LIBUSB_BUNDLED}"

# libmtp loads the bundled libusb beside itself.
install_name_tool \
    -change "${LIBUSB_SOURCE}" \
    "@loader_path/libusb-1.0.0.dylib" \
    "${LIBMTP_BUNDLED}"

# Bundled MTP helper loads libraries from Contents/Frameworks.
install_name_tool \
    -change "${LIBMTP_SOURCE}" \
    "@loader_path/../Frameworks/libmtp.9.dylib" \
    "${HELPER_BINARY}"

install_name_tool \
    -change "${LIBUSB_SOURCE}" \
    "@loader_path/../Frameworks/libusb-1.0.0.dylib" \
    "${HELPER_BINARY}"

# Sakura loads both libraries from Contents/Frameworks.
install_name_tool \
    -change "${LIBMTP_SOURCE}" \
    "@executable_path/../Frameworks/libmtp.9.dylib" \
    "${MACOS_DIR}/${EXECUTABLE_NAME}"

install_name_tool \
    -change "${LIBUSB_SOURCE}" \
    "@executable_path/../Frameworks/libusb-1.0.0.dylib" \
    "${MACOS_DIR}/${EXECUTABLE_NAME}"


if [[ -f "${ICON_SOURCE}" ]]; then
    cp "${ICON_SOURCE}" "${RESOURCES_DIR}/${ICON_NAME}"
fi

LOGO_SOURCE="$ROOT_DIR/Assets/SakuraLogo.png"

if [[ -f "${LOGO_SOURCE}" ]]; then
    cp "${LOGO_SOURCE}" "${RESOURCES_DIR}/SakuraLogo.png"
fi

# Bundle Sakura Switch license and third-party license notices.
SAKURA_LICENSE_SOURCE="$ROOT_DIR/LICENSE.md"
SAKURA_NOTICE_SOURCE="$ROOT_DIR/NOTICE"
THIRD_PARTY_NOTICES_SOURCE="$ROOT_DIR/THIRD_PARTY_NOTICES.md"
THIRD_PARTY_LICENSES_SOURCE="$ROOT_DIR/ThirdPartyLicenses"

if [[ ! -f "${SAKURA_LICENSE_SOURCE}" ]]; then
    echo "❌ Missing LICENSE.md"
    exit 1
fi

if [[ ! -f "${SAKURA_NOTICE_SOURCE}" ]]; then
    echo "❌ Missing NOTICE"
    exit 1
fi

if [[ ! -f "${THIRD_PARTY_NOTICES_SOURCE}" ]]; then
    echo "❌ Missing THIRD_PARTY_NOTICES.md"
    exit 1
fi

if [[ ! -f "${THIRD_PARTY_LICENSES_SOURCE}/LGPL-2.1.txt" ]]; then
    echo "❌ Missing ThirdPartyLicenses/LGPL-2.1.txt"
    exit 1
fi

cp "${SAKURA_LICENSE_SOURCE}"    "${RESOURCES_DIR}/LICENSE.md"

cp "${SAKURA_NOTICE_SOURCE}"    "${RESOURCES_DIR}/NOTICE"

cp "${THIRD_PARTY_NOTICES_SOURCE}"    "${RESOURCES_DIR}/THIRD_PARTY_NOTICES.md"

mkdir -p "${RESOURCES_DIR}/ThirdPartyLicenses"

cp "${THIRD_PARTY_LICENSES_SOURCE}/LGPL-2.1.txt"    "${RESOURCES_DIR}/ThirdPartyLicenses/LGPL-2.1.txt"

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SakuraSwitch</string>
    <key>CFBundleIdentifier</key>
    <string>com.projectsakura.sakuraswitch</string>
    <key>CFBundleName</key>
    <string>Sakura Switch</string>
    <key>CFBundleDisplayName</key>
    <string>Sakura Switch</string>
    <key>CFBundleIconFile</key>
    <string>SakuraSwitch.icns</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# install_name_tool modifies Mach-O files, so create a fresh ad-hoc signature.
codesign --force --deep --sign - "${APP_DIR}"

echo ""
echo "Verifying bundled runtime dependencies..."

echo "--- SakuraSwitch ---"
otool -L "${MACOS_DIR}/${EXECUTABLE_NAME}"

echo "--- libmtp ---"
otool -L "${LIBMTP_BUNDLED}"

echo "--- libusb ---"
otool -L "${LIBUSB_BUNDLED}"

if otool -L \
    "${MACOS_DIR}/${EXECUTABLE_NAME}" \
    "${LIBMTP_BUNDLED}" \
    "${LIBUSB_BUNDLED}" \
    | grep -Eq '/usr/local/opt/|/opt/homebrew/opt/'; then
    echo "❌ Build still contains Homebrew runtime dependencies."
    exit 1
fi

echo "✅ Runtime libraries are self-contained."


echo ""
echo "✅ ${APP_DIR} ready!"
echo ""

if [[ "$INSTALL_TO_APPLICATIONS" == true ]]; then
    echo "Installing to /Applications..."
    rm -rf "$TARGET_APP"
    ditto "$APP_DIR" "$TARGET_APP"
    xattr -dr com.apple.quarantine "$TARGET_APP" || true
    echo "✅ Installed at $TARGET_APP"
    open "$TARGET_APP"
else
    echo "To use:"
    echo "  open \"$ROOT_DIR/build/${APP_NAME}.app\""
    echo "  # or run scripts/build-app.sh --install"
fi
