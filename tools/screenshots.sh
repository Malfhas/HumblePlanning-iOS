#!/usr/bin/env bash
# Screenshots of the App Store listing (AppStoreScreenshots), in English and French, on an iPhone 6.9" and an iPad
# 13" simulator, against a fresh test server filled by seed.mjs (the alerts must hold only the seeded changes).
#
#   HP_SERVER_SRC=<server checkout> HP_ANDROID_REPO=<Android checkout> tools/screenshots.sh
#
# The PNG files go to build/ui-shots/appstore/<iphone|ipad>-<language>-<NN>-<name>.png. The status bar shows 9:41,
# full battery and signal, as Apple's own screenshots do.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${HP_SERVER_SRC:?set HP_SERVER_SRC to a checkout of the Humble Planning server}"
: "${HP_ANDROID_REPO:?set HP_ANDROID_REPO to a checkout of HumblePlanning-Android (its tools/test-server)}"
export HP_SERVER_SRC
DEVICES=("${HP_IPHONE:-iPhone 18 Pro Max}" "${HP_IPAD:-iPad Pro 13-inch (M5)}")

# A fresh server: its database lives in memory, and seed.mjs fills it again around this week
docker compose -p hp-test -f "$HP_ANDROID_REPO/tools/test-server/docker-compose.yml" down
rm -f build/ui-tests-seed-password
rm -rf build/ui-shots/appstore

for device in "${DEVICES[@]}"; do
  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b >/dev/null
  xcrun simctl status_bar "$device" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  TEST_RUNNER_HP_APPSTORE=1 tools/ui-tests.sh "$device" -only-testing:HumblePlanningUITests/AppStoreScreenshots
  xcrun simctl status_bar "$device" clear
done
ls -1 build/ui-shots/appstore
