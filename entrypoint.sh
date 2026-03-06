#!/bin/bash
set -e

echo "=== Initializing environment ==="
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

echo "=== Starting CoppeliaSim (headless mode) ==="

# auto-start simulation and run indefinitely
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
/opt/coppelia/coppeliaSim \
-h \
-s0 \
-G ZmqRemoteApi.rpcPort=23000 \
-G ZmqRemoteApi.cntPort=23001 \
/app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!
echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

echo "=== Waiting for ZMQ remote API server load message ==="

TIMEOUT=180
INTERVAL=3
ELAPSED=0

until grep -iq "zmq" coppeliasim.log 2>/dev/null || [ $ELAPSED -ge $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "waiting... (${ELAPSED}s / ${TIMEOUT}s)"
    tail -n 4 coppeliasim.log 2>/dev/null || true
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: ZMQ remote API server not detected after ${TIMEOUT}s"
    echo "Last 60 lines of coppeliasim.log:"
    tail -n 60 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "ZMQ remote API server addon load message detected."

echo "=== Waiting for port 23000 to bind ==="

PORT_TIMEOUT=120
PORT_ELAPSED=0

until (ss -tuln 2>/dev/null | grep -q ":23000") || [ $PORT_ELAPSED -ge $PORT_TIMEOUT ]; do
    sleep 3
    PORT_ELAPSED=$((PORT_ELAPSED + 3))
    echo "port check... (${PORT_ELAPSED}s / ${PORT_TIMEOUT}s)"
    tail -n 6 coppeliasim.log 2>/dev/null || true
done

if ! ss -tuln 2>/dev/null | grep -q ":23000"; then
    echo "ERROR: Port 23000 not listening"
    echo "Last 80 lines of coppeliasim.log:"
    tail -n 80 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "✓ Port 23000 is listening → ZMQ server ready!"

echo "=== Test discovery debug ==="

ls -la /app/tests 2>/dev/null || echo "Directory /app/tests does NOT exist!"

find /app -name "test_*.py" 2>/dev/null || echo "No tests found!"

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
timeout 12s wait $COPPELIA_PID 2>/dev/null || true

if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "CoppeliaSim still running → forcing kill"
    kill -KILL $COPPELIA_PID 2>/dev/null || true
fi

echo "=== Test finished with exit code $TEST_EXIT_CODE ==="
echo "Last 50 lines of coppeliasim.log:"

tail -n 50 coppeliasim.log

exit $TEST_EXIT_CODE
