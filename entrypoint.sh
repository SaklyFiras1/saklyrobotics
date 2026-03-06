#!/bin/bash
set -e

echo "=== Initializing environment ==="
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

echo "=== Starting CoppeliaSim (headless mode) ==="
# Note: we use capital Z in ZmqRemoteApi (case-sensitive)
# We explicitly load the scene and force ZMQ ports

xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -h \
    -G ZmqRemoteApi.rpcPort=23000 \
    -G ZmqRemoteApi.cntPort=23001 \
    /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!
echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

echo "=== Waiting for ZMQ Remote API server to be ready ==="
TIMEOUT=180
INTERVAL=3
ELAPSED=0

until grep -q "ZMQ remote API server" coppeliasim.log 2>/dev/null || [ $ELAPSED -ge $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo " waiting... (${ELAPSED}s / ${TIMEOUT}s)"
    tail -n 2 coppeliasim.log 2>/dev/null || true
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: ZMQ remote API server did not appear in log after ${TIMEOUT}s"
    echo "Last 60 lines of log:"
    tail -n 60 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "ZMQ addon line detected in log."

echo "Waiting extra time for full initialization, handshake and socket binding..."
sleep 15

echo "=== Checking if ZMQ port 23000 is actually listening ==="
if command -v netstat >/dev/null; then
    if netstat -tuln 2>/dev/null | grep -q ":23000"; then
        echo "✓ Port 23000 is listening"
    else
        echo "✗ Port 23000 is NOT listening yet!"
        tail -n 30 coppeliasim.log
    fi
elif command -v ss >/dev/null; then
    if ss -tuln 2>/dev/null | grep -q ":23000"; then
        echo "✓ Port 23000 is listening"
    else
        echo "✗ Port 23000 is NOT listening yet!"
        tail -n 30 coppeliasim.log
    fi
else
    echo "Warning: netstat/ss not found — cannot check port"
fi

echo "=== Running pytest ==="
export PYTHONPATH=/app

if [ -d "/app/tests" ]; then
    TEST_PATH="tests/"
else
    TEST_PATH="."
fi

pytest $TEST_PATH \
    --html=report.html \
    --self-contained-html \
    --timeout=300 \          # increased to 5 minutes for safety during debug
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
echo "Last 30 lines of coppeliasim.log:"
tail -n 30 coppeliasim.log

exit $TEST_EXIT_CODE
