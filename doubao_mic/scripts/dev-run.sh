#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="VoiceInput.app"
INSTALL_PATH="/Applications/${APP_NAME}"
BUNDLE_ID="com.voiceinput.app"
SCHEME="VoiceInput"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"
LOCAL_SIGNING_FILE="${PROJECT_DIR}/Signing.local.xcconfig"

resolve_local_signing_value() {
  local key="$1"
  local file="$2"
  awk -F '=' -v k="$key" '
    $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
      v=$2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      print v
      exit
    }
  ' "${file}"
}

if [[ -f "${LOCAL_SIGNING_FILE}" ]]; then
  echo "==> Found local signing override: ${LOCAL_SIGNING_FILE}"
  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    LOCAL_TEAM="$(resolve_local_signing_value DEVELOPMENT_TEAM "${LOCAL_SIGNING_FILE}")"
    if [[ -n "${LOCAL_TEAM}" ]]; then
      export DEVELOPMENT_TEAM="${LOCAL_TEAM}"
    fi
  fi
  if [[ -z "${CODE_SIGN_STYLE:-}" ]]; then
    LOCAL_SIGN_STYLE="$(resolve_local_signing_value CODE_SIGN_STYLE "${LOCAL_SIGNING_FILE}")"
    if [[ -n "${LOCAL_SIGN_STYLE}" ]]; then
      export CODE_SIGN_STYLE="${LOCAL_SIGN_STYLE}"
    fi
  fi
  if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
    LOCAL_SIGN_IDENTITY="$(resolve_local_signing_value CODE_SIGN_IDENTITY "${LOCAL_SIGNING_FILE}")"
    if [[ -n "${LOCAL_SIGN_IDENTITY}" ]]; then
      export CODE_SIGN_IDENTITY="${LOCAL_SIGN_IDENTITY}"
    fi
  fi
fi

echo "==> Building ${SCHEME} (${CONFIGURATION})"
BUILD_ARGS=(
  -project "${PROJECT_DIR}/VoiceInput.xcodeproj"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "${DESTINATION}"
)
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "==> Using development team: ${DEVELOPMENT_TEAM}"
  BUILD_ARGS+=(
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}"
    CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Automatic}"
    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}"
  )
fi
xcodebuild "${BUILD_ARGS[@]}" build >/tmp/voiceinput_dev_run_build.log

echo "==> Resolving build output"
APP_PATH="$(
  xcodebuild "${BUILD_ARGS[@]}" -showBuildSettings 2>/dev/null \
    | awk '
      /TARGET_BUILD_DIR = / { build_dir=$3 }
      /FULL_PRODUCT_NAME = / { product_name=$3 }
      END {
        if (build_dir != "" && product_name != "") {
          print build_dir "/" product_name
        }
      }
    '
)"
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "ERROR: unable to locate built app path"
  exit 1
fi

echo "==> Installing to ${INSTALL_PATH}"
pkill -f "${INSTALL_PATH}/Contents/MacOS/VoiceInput" >/dev/null 2>&1 || true
ditto "${APP_PATH}" "${INSTALL_PATH}"

echo "==> Launching app"
open "${INSTALL_PATH}"
sleep 1

PID="$(pgrep -f "${INSTALL_PATH}/Contents/MacOS/VoiceInput" | head -n 1 || true)"
if [[ -z "${PID}" ]]; then
  echo "ERROR: app launch failed"
  exit 1
fi

echo "==> Running self-check"
echo "PID=${PID}"
echo "APP_PATH=${INSTALL_PATH}"
echo "BUNDLE_ID=${BUNDLE_ID}"
echo
echo "[codesign]"
codesign -dvv "${INSTALL_PATH}" 2>&1 | rg -n "Identifier=|TeamIdentifier=|Signature=|Authority=" || true
echo
echo "[defaults]"
echo -n "logLevel="
defaults read "${BUNDLE_ID}" logLevel 2>/dev/null || echo "unset"
echo
echo "[tcc-db]"
sqlite3 "${HOME}/Library/Application Support/com.apple.TCC/TCC.db" \
  "select service,client,auth_value,auth_reason,last_modified from access where client='${BUNDLE_ID}' order by service;" || true
echo
echo "[recent-permission-logs]"
/usr/bin/log show --style compact --last 3m --predicate "processID == ${PID} && subsystem == \"com.voiceinput.app\"" \
  | rg -n "Permission snapshot|Accessibility trust|PostEvent permission|ListenEvent permission|Microphone permission|attemptId" || true

echo
echo "Tip: if Signature=adhoc or TeamIdentifier=not set, TCC permissions may be unstable in development."
