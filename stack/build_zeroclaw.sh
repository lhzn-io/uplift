#!/bin/bash

# Navigate to the zeroclaw directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/zeroclaw" || exit 1

echo "=========================================================="
echo "🚀 Starting ZeroClaw Build (Profile: release-fast)"
echo "=========================================================="

VERBOSE=${VERBOSE:-1}

# sandbox-landlock compiles in the Landlock backend selected by
# [risk_profiles.default] in configs/zeroclaw-*.toml.template. channel-slack is
# not a default feature since ZeroClaw v0.8.5. plugins-wasm is left out on
# purpose: the agents load no WASM plugins, and omitting it keeps the wasmtime
# sandbox (and its advisories) out of the binary. The uplift trace observer is
# part of the lab fork branch (UPLIFT_TRACE_PATH), so no source patching happens here.
CARGO_FEATURES=${CARGO_FEATURES:-browser-native,sandbox-landlock,channel-slack}

# The build log lives outside the submodule so the fork checkout stays clean.
LOG_FILE="$DIR/cargo_build.log"

# The dashboard bundle (web/dist) is copied into the image by Dockerfile.zeroclaw.
# It is built with upstream's `cargo web build`, which renders the gateway's
# OpenAPI spec and generates the TypeScript client with npm/npx (Node.js 24 from
# jetson/bootstrap_devbox.sh), and is rebuilt whenever the ZeroClaw commit changes.
REBUILD_WEB=${REBUILD_WEB:-0}
WEB_STAMP=web/dist/.zeroclaw-commit

# Start a background timer that prints the elapsed time on a single line
START=$(date +%s)
timer() {
  while true; do
      NOW=$(date +%s)
      ELAPSED=$((NOW - START))
      MINS=$((ELAPSED / 60))
      SECS=$((ELAPSED % 60))
      
      # Use carriage return \r to overwrite the line, \e[K clears the rest of the line
      printf "\r\e[K[ ⏳ Elapsed Time: %02dm %02ds ] Compiling in background..." "$MINS" "$SECS"
      sleep 1
  done
}

if [ "$VERBOSE" -eq 1 ]; then
    echo "Running in verbose mode..."
    (
        while true; do
            sleep 30
            NOW=$(date +%s)
            ELAPSED=$((NOW - START))
            MINS=$((ELAPSED / 60))
            SECS=$((ELAPSED % 60))
            echo "=== [ ⏳ Elapsed Time: ${MINS}m ${SECS}s ] Still compiling... ==="
        done
    ) &
    TIMER_PID=$!

    cargo build --profile release-fast --features "$CARGO_FEATURES" 2>&1 | tee "$LOG_FILE"
    EXIT_CODE=${PIPESTATUS[0]}
    
    kill $TIMER_PID 2>/dev/null
    wait $TIMER_PID 2>/dev/null
else
    # Launch the timer in the background
    timer &
    TIMER_PID=$!

    # Run cargo build and redirect output to a log file so it doesn't garble the timer
    cargo build --profile release-fast --features "$CARGO_FEATURES" > "$LOG_FILE" 2>&1
    EXIT_CODE=$?

    # Kill the background timer
    kill $TIMER_PID 2>/dev/null
    wait $TIMER_PID 2>/dev/null
    printf "\r\e[K\n"
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Build finished successfully!"
    echo "⏱️  Final Duration: $(( $(date +%s) - START )) seconds."
else
    echo "❌ Build failed with exit code $EXIT_CODE"
    echo "--- Last 20 lines of build log ---"
    tail -n 20 "$LOG_FILE"
    echo "----------------------------------"
    echo "Check stack/cargo_build.log for the full error."
fi

HEAD_COMMIT=$(git rev-parse HEAD)
if [ $EXIT_CODE -eq 0 ] && { [ "$REBUILD_WEB" = "1" ] || [ "$(cat "$WEB_STAMP" 2>/dev/null)" != "$HEAD_COMMIT" ]; }; then
    echo "Building dashboard bundle (web/dist) for ${HEAD_COMMIT:0:9} with cargo web build..."
    if ! command -v npm >/dev/null 2>&1; then
        echo "npm not found: run ./jetson/bootstrap_devbox.sh to install Node.js 24"
        exit 1
    fi
    cargo web build
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
        echo "$HEAD_COMMIT" > "$WEB_STAMP"
    else
        echo "Dashboard build failed with exit code $EXIT_CODE"
    fi
fi

exit $EXIT_CODE
