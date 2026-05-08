#!/bin/bash

# Navigate to the zeroclaw directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/zeroclaw" || exit 1

echo "=========================================================="
echo "🚀 Starting ZeroClaw Build (Profile: release-fast)"
echo "=========================================================="

VERBOSE=${VERBOSE:-1}

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

export OBS_PATCH='let obs = crate::hooks::uplift::UpliftObserver::new(); runner.register(Box::new(obs));'
awk '/\[dependencies\]/ { print; print "uplift = { path = \"../../../../crates/uplift\" }"; next }1' crates/zeroclaw-runtime/Cargo.toml > crates/zeroclaw-runtime/Cargo.toml.tmp && mv crates/zeroclaw-runtime/Cargo.toml.tmp crates/zeroclaw-runtime/Cargo.toml
awk '/HookRunner::new/ { print; print "                " ENVIRON["OBS_PATCH"]; next }1' crates/zeroclaw-runtime/src/agent/agent.rs > agent.rs.tmp && mv agent.rs.tmp crates/zeroclaw-runtime/src/agent/agent.rs

cat ../../crates/uplift-observer/src/lib.rs | sed 's/zeroclaw_runtime::hooks/super/g' > crates/zeroclaw-runtime/src/hooks/uplift.rs
awk '/mod traits;/ { print; print "pub mod uplift;"; next }1' crates/zeroclaw-runtime/src/hooks/mod.rs > hooks_mod.tmp && mv hooks_mod.tmp crates/zeroclaw-runtime/src/hooks/mod.rs

export LOOP_PATCH='    let hook_runner = if config.hooks.enabled { let mut r = crate::hooks::HookRunner::new(); let obs = crate::hooks::uplift::UpliftObserver::new(); r.register(Box::new(obs)); Some(std::sync::Arc::new(r)) } else { None };'
awk '/let fallback_provider_loop / { print; print ENVIRON["LOOP_PATCH"]; next } { print }' crates/zeroclaw-runtime/src/agent/loop_.rs > loop.tmp && mv loop.tmp crates/zeroclaw-runtime/src/agent/loop_.rs

awk '
/pub async fn run\(/ { in_run=1; print; next }
/^}/ { if (in_run) in_run=0; print; next }
in_run && /run_tool_call_loop\(/ { in_loop=1; print; next }
in_run && in_loop && /config\.agent\.max_tool_iterations,/ {
    print;
    getline; print;
    getline; print;
    getline;
    if ($0 ~ /None,/) {
        print "                        hook_runner.as_deref(),";
    } else {
        print;
    }
    in_loop=0;
    next
}
{ print }
' crates/zeroclaw-runtime/src/agent/loop_.rs > loop2.tmp && mv loop2.tmp crates/zeroclaw-runtime/src/agent/loop_.rs

trap "git restore crates/zeroclaw-runtime/Cargo.toml crates/zeroclaw-runtime/src/agent/agent.rs crates/zeroclaw-runtime/src/agent/loop_.rs crates/zeroclaw-runtime/src/hooks/mod.rs && rm -f crates/zeroclaw-runtime/src/hooks/uplift.rs" EXIT

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

    cargo build --profile release-fast --features browser-native 2>&1 | tee cargo_build.log
    EXIT_CODE=${PIPESTATUS[0]}
    
    kill $TIMER_PID 2>/dev/null
    wait $TIMER_PID 2>/dev/null
else
    # Launch the timer in the background
    timer &
    TIMER_PID=$!

    # Run cargo build and redirect output to a log file so it doesn't garble the timer
    cargo build --profile release-fast --features browser-native > cargo_build.log 2>&1
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
    tail -n 20 cargo_build.log
    echo "----------------------------------"
    echo "Check stack/zeroclaw/cargo_build.log for the full error."
fi

exit $EXIT_CODE
