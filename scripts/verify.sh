#!/usr/bin/env bash
# verify.sh — machine-checkable pass/fail oracle for the agentic coding loop.
#
# Usage:
#   scripts/verify.sh backend   — runs the FastAPI/pytest suite
#   scripts/verify.sh ios       — builds and tests the iOS app on Simulator
#
# Exit 0 = green. Exit non-zero = red.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "Usage: $0 <surface>"
  echo "  backend  — run pytest against the FastAPI backend"
  echo "  ios      — run xcodebuild test against the iOS Simulator"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

SURFACE="$1"

case "$SURFACE" in

  backend)
    echo "==> Verifying backend (pytest)"
    cd "$REPO_ROOT/backend"
    .venv/bin/pytest -q
    ;;

  ios)
    echo "==> Verifying iOS (xcodebuild test)"

    # Resolve a concrete simulator destination
    DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4"

    # Fail loudly if xcodebuild is not found
    if ! command -v xcodebuild &>/dev/null; then
      echo "ERROR: xcodebuild not found. Install Xcode and run 'sudo xcode-select --switch /Applications/Xcode.app'."
      exit 1
    fi

    # Confirm the runtime is installed (fast check before a slow build)
    if ! xcrun simctl list runtimes available 2>/dev/null | grep -q "iOS 26.4"; then
      echo "ERROR: iOS 26.4 Simulator runtime not installed."
      echo "Open Xcode → Settings → Platforms and install the iOS 26 Simulator."
      exit 1
    fi

    xcodebuild test \
      -project "$REPO_ROOT/MyServeCoach/MyServeCoach.xcodeproj" \
      -scheme MyServeCoach \
      -destination "$DESTINATION" \
      -quiet \
      2>&1 | tail -30
    ;;

  *)
    echo "ERROR: Unknown surface '$SURFACE'."
    usage
    ;;

esac
