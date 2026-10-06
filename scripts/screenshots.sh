#!/usr/bin/env bash
# Captures README screenshots of the example app on an iPhone and an iPad simulator.
# Usage: scripts/screenshots.sh <Scheme> <bundle id> --iphone <scene> [<scene> ...] --ipad <scene> [<scene> ...]
# Writes docs/screenshots/<device>-<scene>.png, for example iphone-grid.png and ipad-gallery.png.
# Exits with an error instead of keeping a blank or stale capture.
set -euo pipefail

SCHEME="$1"; BUNDLE_ID="$2"; shift 2
IPHONE_SCENES=()
IPAD_SCENES=()
target=""
for argument in "$@"; do
  case "$argument" in
    --iphone) target=iphone ;;
    --ipad) target=ipad ;;
    *)
      case "$target" in
        iphone) IPHONE_SCENES+=("$argument") ;;
        ipad) IPAD_SCENES+=("$argument") ;;
        *) echo "Scene $argument must follow --iphone or --ipad" >&2; exit 1 ;;
      esac
      ;;
  esac
done
if [ ${#IPHONE_SCENES[@]} -eq 0 ] && [ ${#IPAD_SCENES[@]} -eq 0 ]; then
  echo "No scenes given" >&2
  exit 1
fi
OUT="docs/screenshots"
MIN_BYTES=100000
mkdir -p "$OUT"

# Newest iOS runtime, used only when a simulator has to be created.
RUNTIME=$(xcrun simctl list runtimes available -j | jq -r '
  [.runtimes[] | select(.identifier | test("iOS"))]
  | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty')

# pick_device <family> <preferred name pattern> ...
# Prints the UDID of an available simulator of the family ("iPhone" or "iPad") on the newest iOS
# runtime, preferring the first pattern that matches. Creates one when none exists.
pick_device() {
  local family="$1"; shift
  local devices udid pattern type
  devices=$(xcrun simctl list devices available -j | jq -c --arg family "^$family" '
    [.devices | to_entries | sort_by(.key) | reverse | .[]
     | select(.key | test("iOS")) | .value[] | select(.name | test($family))]')
  for pattern in "$@"; do
    udid=$(jq -r --arg pattern "$pattern" 'map(select(.name | test($pattern))) | .[0].udid // empty' <<< "$devices")
    if [ -n "$udid" ]; then echo "$udid"; return; fi
  done
  udid=$(jq -r '.[0].udid // empty' <<< "$devices")
  if [ -z "$udid" ]; then
    type=$(xcrun simctl list devicetypes -j | jq -r --arg family "^$family" '
      [.devicetypes[] | select(.name | test($family))] | last | .identifier // empty')
    if [ -z "$type" ] || [ -z "$RUNTIME" ]; then
      echo "No $family simulator, device type or iOS runtime available" >&2
      exit 1
    fi
    udid=$(xcrun simctl create "Screenshots $family" "$type" "$RUNTIME")
  fi
  echo "$udid"
}

IPHONE=$(pick_device iPhone "^iPhone [0-9]+ Pro$" "Pro$" "^iPhone [0-9]+$")
IPAD=$(pick_device iPad "^iPad Pro 13" "^iPad Pro" "^iPad Air 13" "^iPad Air")
echo "Using iPhone simulator $IPHONE and iPad simulator $IPAD"

xcodebuild build \
  -project "Example/$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -destination "id=$IPHONE" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= | tail -n 5

APP=$(find build/Build/Products -name "$SCHEME.app" -maxdepth 2 | head -n 1)
if [ -z "$APP" ]; then
  echo "Build product $SCHEME.app not found" >&2
  exit 1
fi

# valid_capture <file> <previous capture or empty>
# A blank frame (app still launching) compresses to a tiny PNG, and a capture identical to the
# previous scene means the app never switched scenes.
valid_capture() {
  local file="$1" previous="$2"
  [ -s "$file" ] || return 1
  [ "$(wc -c < "$file")" -gt "$MIN_BYTES" ] || return 1
  sips -g pixelWidth "$file" > /dev/null 2>&1 || return 1
  if [ -n "$previous" ] && cmp -s "$file" "$previous"; then
    return 1
  fi
  return 0
}

# capture <udid> <device label> <scene> [<scene> ...]: boots the simulator, captures every scene,
# shuts it down again, so `booted` always means this one simulator.
capture() {
  local udid="$1" device="$2" scene file previous="" attempt ok waited
  shift 2
  local scenes=("$@")
  xcrun simctl shutdown all > /dev/null 2>&1 || true
  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  xcrun simctl ui "$udid" appearance light
  xcrun simctl install "$udid" "$APP"
  local container home
  container=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)
  # A first boot can still be setting up the home screen; give it time, then keep a capture of
  # it so a frame where the app never came to the front is rejected.
  sleep 10
  home="$OUT/.home-$device.png"
  xcrun simctl io "$udid" screenshot "$home"

  for scene in "${scenes[@]}"; do
    file="$OUT/$device-$scene.png"
    ok=""
    for attempt in 1 2 3; do
      xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
      sleep 1
      rm -f "$container/tmp/screenshot-ready"
      xcrun simctl launch "$udid" "$BUNDLE_ID" -screenshot "$scene"
      # The app writes this marker once the scene is on screen.
      waited=0
      while [ ! -f "$container/tmp/screenshot-ready" ] && [ "$waited" -lt 60 ]; do
        sleep 1
        waited=$((waited + 1))
      done
      if [ ! -f "$container/tmp/screenshot-ready" ]; then
        echo "The app did not show $scene on $device, retrying"
        continue
      fi
      sleep $((3 + attempt * 2))
      rm -f "$file"
      xcrun simctl io "$udid" screenshot "$file"
      if valid_capture "$file" "$previous" && ! cmp -s "$file" "$home"; then
        ok=1
        break
      fi
      echo "Blank or stale capture for $device-$scene, retrying"
    done
    if [ -z "$ok" ]; then
      echo "Capture for $device-$scene is still blank; refusing to commit a broken screenshot." >&2
      rm -f "$file"
      exit 1
    fi
    previous="$file"
    echo "Captured $file ($(wc -c < "$file") bytes)"
  done

  rm -f "$home"
  xcrun simctl shutdown "$udid" || true
}

if [ ${#IPHONE_SCENES[@]} -gt 0 ]; then
  capture "$IPHONE" iphone "${IPHONE_SCENES[@]}"
fi
if [ ${#IPAD_SCENES[@]} -gt 0 ]; then
  capture "$IPAD" ipad "${IPAD_SCENES[@]}"
fi
