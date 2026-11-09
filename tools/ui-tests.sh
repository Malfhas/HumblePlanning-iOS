#!/usr/bin/env bash
# Interface tests of the app against a disposable Humble Planning server, the test server of the Android
# repository (Docker, http://localhost:3100, stand-ins for the AI provider and push), filled with the fictitious
# company of its tools/screenshots/seed.mjs.
#
#   HP_SERVER_SRC=<server checkout> HP_ANDROID_REPO=<Android checkout> tools/ui-tests.sh [simulator] [-only-testing:…]
#
# Everything lives in memory and is thrown away with `docker compose -p hp-test down`. Screenshots of every step
# go to build/ui-shots/. The server only listens on this computer.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${HP_SERVER_SRC:?set HP_SERVER_SRC to a checkout of the Humble Planning server}"
: "${HP_ANDROID_REPO:?set HP_ANDROID_REPO to a checkout of HumblePlanning-Android (its tools/test-server)}"
SIMULATOR=${1:-iPhone 17}
shift || true
COMPOSE=(docker compose -p hp-test -f "$HP_ANDROID_REPO/tools/test-server/docker-compose.yml")
export HP_SERVER_SRC

if ! curl -fsS -o /dev/null http://localhost:3100/login 2>/dev/null; then
  "${COMPOSE[@]}" up -d --build
  until curl -fsS -o /dev/null http://localhost:3100/login 2>/dev/null; do sleep 3; done
fi
# The test administrator (an account already there is kept)
echo 'TestAdmin2026!x' | "${COMPOSE[@]}" exec -T web bun src/scripts/provision.ts create-admin testadmin || true
# The seeded company, once per server (its accounts share the password the script prints)
if [ ! -s build/ui-tests-seed-password ]; then
  mkdir -p build
  node "$HP_ANDROID_REPO/tools/screenshots/seed.mjs" | tee build/ui-tests-seed.log
  sed -n 's/.*password[^:]*: *\([^ ]*\).*/\1/p' build/ui-tests-seed.log | tail -n 1 >build/ui-tests-seed-password
fi

mkdir -p build/ui-shots
# The whole suite, unless the arguments name the tests to run (-only-testing:HumblePlanningUITests/…)
ONLY=(-only-testing:HumblePlanningUITests)
for arg in "$@"; do [[ $arg == -only-testing:* ]] && ONLY=(); done
# (macOS's bash 3.2 calls an empty array unbound under `set -u`: hence ${ONLY[@]+…} below)
TEST_RUNNER_HP_UITESTS=1 TEST_RUNNER_HP_SHOTS="$PWD/build/ui-shots" \
TEST_RUNNER_HP_SEED_PASSWORD="$(cat build/ui-tests-seed-password)" \
  xcodebuild -project HumblePlanning.xcodeproj -scheme HumblePlanning -derivedDataPath build/DerivedData \
    -destination "platform=iOS Simulator,name=$SIMULATOR" ${ONLY[@]+"${ONLY[@]}"} "$@" test
