#!/bin/bash
set -e

echo "=== Initializing environment ==="

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

mkdir -p output

echo "=== Starting CoppeliaSim (headless mode) ==="

# Start CoppeliaSim in headless mode under Xvfb
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -s \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.bindingAddress=0.0.0.0 \
    /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

echo "=== Waiting for ZMQ Remote API server to be ready ==="

# Wait for simZMQ plugin to be fully loaded
TIMEOUT=180   # give it up to 3 minutes
INTERVAL=2
ELAPSED=0

until grep -q "plugin simZMQ: done" coppeliasim.log 2>/dev/null; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "  waiting... (${ELAPSED}s / ${TIMEOUT}s)"
    tail -n 5 coppeliasim.log || true

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERROR: ZMQ remote API server did not appear in log after ${TIMEOUT}s"
        tail -n 40 coppeliasim.log
        kill -TERM $COPPELIA_PID 2>/dev/null || true
        exit 1
    fi
done

echo "CoppeliaSim ZMQ server addon loaded. Waiting for scene to settle..."
sleep 5   # give simulation a moment to initialize

# Optional: print last 10 lines of log to debug
tail -n 10 coppeliasim.log

echo "=== Running pytest ==="

export PYTHONPATH=/app

TEST_PATH="tests/"  # explicitly set tests folder

pytest $TEST_PATH \
    --html=report.html \
    --self-contained-html \
    --timeout=300 \
    --timeout-method=thread \
    -vv

TEST_EXIT_CODE=$?

echo "=== Stopping CoppeliaSim ==="

kill -TERM $COPPELIA_PID 2>/dev/null || true
timeout 10s wait $COPPELIA_PID 2>/dev/null || true

if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "CoppeliaSim still alive → force kill"
    kill -KILL $COPPELIA_PID 2>/dev/null || true
fi

echo "=== Test finished with exit code $TEST_EXIT_CODE ==="
echo "Last 20 lines of coppeliasim.log:"
tail -n 20 coppeliasim.log

exit $TEST_EXIT_CODE
