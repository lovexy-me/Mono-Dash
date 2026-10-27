#!/bin/zsh
# Build the Android app on the Windows host (DEV) and copy the result back.
#
#   scripts/remote_build/remote_build_android.sh [aab|apk] [--debug|--profile|--release]
#       [--install] [--allow-flutter-mismatch] [-- <extra flutter build args>]
#
# With no arguments it builds a release AAB, signed with the upload key kept in
# D:\Builds\mono_dash\secrets on the Windows host.
#
# Zips lib/, assets/, android/ and the pubspec files (tracked + untracked, minus
# git-ignored), so uncommitted changes are included. Artifacts land in
# build/remote/<timestamp>/.
#
# Env overrides: MONO_BUILD_HOST (user@host), MONO_BUILD_LAN, MONO_BUILD_TS.
set -euo pipefail

KIND=appbundle
MODE=release
INSTALL=0
ALLOW_MISMATCH=false
EXTRA=()

while (( $# )); do
  case "$1" in
    apk|appbundle) KIND=$1 ;;
    aab) KIND=appbundle ;;
    --debug|--profile|--release) MODE=${1#--} ;;
    --install) INSTALL=1 ;;
    --allow-flutter-mismatch) ALLOW_MISMATCH=true ;;
    --) shift; EXTRA=("$@"); break ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

cd "$(dirname "$0")/../.."
REPO=$PWD

# Pick the LAN address when reachable, otherwise Tailscale.
LAN=${MONO_BUILD_LAN:-192.168.110.89}
TS=${MONO_BUILD_TS:-100.111.111.112}
if [[ -n "${MONO_BUILD_HOST:-}" ]]; then
  HOST=$MONO_BUILD_HOST
elif nc -z -G 2 "$LAN" 22 2>/dev/null; then
  HOST=mou@$LAN
else
  HOST=mou@$TS
fi

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8
  -o ControlMaster=auto -o "ControlPath=$HOME/.ssh/cm-%r@%h:%p" -o ControlPersist=120)
INBOX=mono_build_inbox   # relative to the remote user's home

FLUTTER_VERSION=$(flutter --version 2>/dev/null | awk 'NR==1 {print $2}')
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$REPO/build/remote/$STAMP"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

echo "==> Packing ($KIND, $MODE, Flutter $FLUTTER_VERSION) for $HOST"
{
  git ls-files -co --exclude-standard -- lib assets android \
    pubspec.yaml pubspec.lock l10n.yaml analysis_options.yaml
  # Git-ignored, but pins the Gradle version Flutter would otherwise pick.
  echo android/gradle/wrapper/gradle-wrapper.properties
} | while IFS= read -r f; do if [[ -f "$f" ]]; then echo "$f"; fi; done \
  | zip -q -X "$WORK/src.zip" -@
echo "    src.zip $(du -h "$WORK/src.zip" | cut -f1)"

python3 - "$WORK/job.json" "$KIND" "$MODE" "$FLUTTER_VERSION" "$ALLOW_MISMATCH" "${EXTRA[@]}" <<'PY'
import json, sys
path, kind, mode, version, allow, *extra = sys.argv[1:]
json.dump({"kind": kind, "mode": mode,
           "flutterVersion": version, "allowFlutterMismatch": allow == "true",
           "extraArgs": extra}, open(path, "w"))
PY
cp scripts/remote_build/build.ps1 "$WORK/build.ps1"

echo "==> Uploading"
ssh "${SSH_OPTS[@]}" "$HOST" "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force $INBOX | Out-Null\""
scp -q "${SSH_OPTS[@]}" "$WORK/src.zip" "$WORK/job.json" "$WORK/build.ps1" "$HOST:$INBOX/"

echo "==> Building on Windows"
START=$SECONDS
set +e
ssh "${SSH_OPTS[@]}" "$HOST" "powershell -NoProfile -ExecutionPolicy Bypass -File $INBOX/build.ps1" 2>&1 \
  | tee "$OUT/build.log"
STATUS=${pipestatus[1]}
set -e
if (( STATUS != 0 )); then
  echo "Remote build failed (exit $STATUS). Log: $OUT/build.log" >&2
  exit $STATUS
fi

echo "==> Downloading artifacts"
scp -q -r "${SSH_OPTS[@]}" "$HOST:$INBOX/out/*" "$OUT/"
ls -lh "$OUT" | grep -vE "build.log|^total"
echo "==> Done in $((SECONDS - START))s -> $OUT"

if (( INSTALL )) && [[ "$KIND" == apk ]]; then
  apk=$(ls "$OUT"/*.apk | head -1)
  echo "==> adb install $apk"
  adb install -r "$apk"
fi
