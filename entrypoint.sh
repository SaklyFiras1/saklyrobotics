#!/bin/bash
set -e

echo "=== Initializing environment ==="
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

echo "=== Starting CoppeliaSim (headless mode) ==="
# Critical fixes:
# - -S : auto-start simulation to prevent immediate exit
# - -G ZmqRemoteApi... : correct capitalization for parameters
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -h \
    -S \
    -G ZmqRemoteApi.rpcPort=23000 \
    -G ZmqRemoteApi.cntPort=23001 \
    /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!
echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

echo "=== Waiting for ZMQ addon load message in log ==="
TIMEOUT=180
INTERVAL=3
ELAPSED=0
until grep -q "ZMQ remote API server" coppeliasim.log 2>/dev/null || [ $ELAPSED -ge $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo " waiting... (${ELAPSED}s / ${TIMEOUT}s)"
    tail -n 3 coppeliasim.log 2>/dev/null || true
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: ZMQ addon load message not found after ${TIMEOUT}s"
    tail -n 60 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "ZMQ addon load detected."

echo "=== Waiting for ZMQ port 23000 to bind (up to 90s) ==="
PORT_TIMEOUT=90
PORT_ELAPSED=0

until (netstat -tuln 2>/dev/null | grep -q ":23000" || ss -tuln 2>/dev/null | grep -q ":23000") || [ $PORT_ELAPSED -ge $PORT_TIMEOUT ]; do
    sleep 3
    PORT_ELAPSED=$((PORT_ELAPSED + 3))
    echo "  checking port... (${PORT_ELAPSED}s / ${PORT_TIMEOUT}s)"
    tail -n 5 coppeliasim.log 2>/dev/null || true
done

if ! (netstat -tuln 2>/dev/null | grep -q ":23000" || ss -tuln 2>/dev/null | grep -q ":23000"); then
    echo "ERROR: Port 23000 did NOT bind after ${PORT_TIMEOUT}s!"
    echo "Last 60 lines of coppeliasim.log:"
    tail -n 60 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "✓ Port 23000 is bound – ZMQ server should be ready!"

# Debug why pytest might find 0 tests
echo "=== Debugging test discovery ==="
ls -la /app/tests 2>/dev/null || echo "Directory /app/tests does NOT exist!"
find /app -name "*test*.py" -o -name "test_*.py" 2>/dev/null || echo "No test files found!"

echo "=== Running pytest ==="
export PYTHONPATH=/app

pytest tests/ \
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
echo "Last 40 lines of coppeliasim.log:"
tail -n 40 coppeliasim.log

exit $TEST_EXIT_CODE
