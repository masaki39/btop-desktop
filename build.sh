#!/usr/bin/env bash
# Builds BtopDesktop.app.
#   ./build.sh            -> creates build/BtopDesktop.app
#   ./build.sh install    -> also copies it to /Applications
#   ./build.sh run        -> builds, then launches it
# Environment variables:
#   CONFIG=debug|release  (default: release)
#   SIGN_IDENTITY=...     (default: "-" = ad-hoc signature)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BtopDesktop"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/${APP_NAME}.app"

echo "==> swift build (-c ${CONFIG})"
swift build -c "${CONFIG}" --arch arm64 --product "${APP_NAME}"
BIN_DIR="$(swift build -c "${CONFIG}" --arch arm64 --show-bin-path)"

echo "==> assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"
# Bundle SwiftPM resource bundles, if any
shopt -s nullglob
for bundle in "${BIN_DIR}"/*.bundle; do
    cp -R "${bundle}" "${APP}/Contents/Resources/"
done
shopt -u nullglob

echo "==> codesign (${SIGN_IDENTITY})"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    TIMESTAMP="--timestamp=none"
else
    TIMESTAMP="--timestamp" # secure timestamp, required for notarization
fi
codesign --force --options runtime "${TIMESTAMP}" --sign "${SIGN_IDENTITY}" "${APP}"
codesign --verify --strict "${APP}"

echo "==> done: ${APP}"

case "${1:-}" in
    install)
        DEST="/Applications/${APP_NAME}.app"
        if pgrep -x "${APP_NAME}" >/dev/null; then
            echo "==> quitting running ${APP_NAME}"
            pkill -x "${APP_NAME}" || true
            sleep 1
        fi
        rm -rf "${DEST}"
        ditto "${APP}" "${DEST}"
        echo "==> installed: ${DEST}"
        ;;
    run)
        pkill -x "${APP_NAME}" 2>/dev/null && sleep 1 || true
        open "${APP}"
        ;;
esac
