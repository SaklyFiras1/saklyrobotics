#!/bin/bash

set -euo pipefail

echo "======================================="
echo " CoppeliaSim CI Runtime"
echo "======================================="

########################################
# Environment setup
########################################

echo "[INIT] Initializing runtime environment"

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

LOG_FILE="coppeliasim.log"
PORT=23000

########################################
# Check required binaries
########################################

echo "[CHECK] Checking dependencies"

command -v xvfb-run >/dev/null || { echo "ERROR: xvfb-run not installed"; exit 1; }
command -v ss >/dev/null || { echo "ERROR: ss command not installed"; exit 1; }

if [ ! -f /opt/coppelia/coppeliaSim ]; then
    echo "ERROR: CoppeliaSim binary not found at /opt/coppelia/coppeliaSim"
    exit 1
fi

########################################
# Start CoppeliaSim
########################################

echo "[START] Launching CoppeliaSim headless"

xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
/opt/coppelia/coppeliaSim \
-h \
-s \
-G ZmqRemoteApi.rpcPort=23000 \
-G ZmqRemoteApi.cntPort=23001 \
/app/pick_and_place.ttt > "$LOG_FILE" 2>&1 &

COPPELIA_PID=$!

echo "[INFO] CoppeliaSim PID: $COPPELIA_PID"
echo "[INFO] Log file: $LOG_FILE"

sleep 5

########################################
# Check if process died early
########################################

if ! kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "ERROR: CoppeliaSim exited immediately"
    echo "------ LOG OUTPUT ------"
    cat "$LOG_FILE"
    exit 1
fi

########################################
# Wait for ZMQ server initialization
########################################

echo "[WAIT] Waiting for ZMQ server initialization"

TIMEOUT=180
INTERVAL=3
ELAPSED=0

while true; do

    if grep -iq "zmq" "$LOG_FILE"; then
        echo "[OK] ZMQ addon detected"
        break
    fi

    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "ERROR: CoppeliaSim crashed during startup"
        echo "------ LOG OUTPUT ------"
        cat "$LOG_FILE"
        exit 1
    fi

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERROR: ZMQ server did not start after $TIMEOUT seconds"
        tail -n 80 "$LOG_FILE"
        kill -TERM $COPPELIA_PID || true
        exit 1
    fi

    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))

    echo "[WAIT] ${ELAPSED}s / ${TIMEOUT}s"
    tail -n 4 "$LOG_FILE"

done

########################################
# Wait for port binding
########################################

echo "[WAIT] Waiting for port $PORT to open"

PORT_TIMEOUT=120
PORT_ELAPSED=0

while true; do

    if ss -tuln | grep -q ":$PORT"; then
        echo "[OK] Port $PORT is listening"
        break
    fi

    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "ERROR: CoppeliaSim crashed before port opened"
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    if [ $PORT_ELAPSED -ge $PORT_TIMEOUT ]; then
        echo "ERROR: Port $PORT not opened after $PORT_TIMEOUT seconds"
        echo "------ LOG OUTPUT ------"
        tail -n 120 "$LOG_FILE"
        kill -TERM $COPPELIA_PID || true
        exit 1
    fi

    sleep 3
    PORT_ELAPSED=$((PORT_ELAPSED + 3))

    echo "[WAIT] port check ${PORT_ELAPSED}s / ${PORT_TIMEOUT}s"
    tail -n 6 "$LOG_FILE"

done

########################################
# Debug test discovery
########################################

echo "[DEBUG] Test discovery"

if [ -d /app/tests ]; then
    ls -la /app/tests
else
    echo "WARNING: /app/tests directory not found"
fi

echo "[DEBUG] Python files found"

find /app -name "*.py" || true

########################################
# Run tests
########################################

echo "[TEST] Running pytest"

export PYTHONPATH=/app

pytest tests/ \
--html=report.html \
--self-contained-html \
--timeout=300 \
--timeout-method=thread \
-vv

TEST_EXIT_CODE=$?

########################################
# Shutdown CoppeliaSim
########################################

echo "[STOP] Stopping CoppeliaSim"

kill -TERM $COPPELIA_PID 2>/dev/null || true
timeout 10s wait $COPPELIA_PID 2>/dev/null || true

if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "[WARN] Process still alive → forcing kill"
    kill -KILL $COPPELIA_PID 2>/dev/null || true
fi

########################################
# Final logs
########################################

echo "======================================="
echo " Test finished with exit code $TEST_EXIT_CODE"
echo "======================================="

echo "[LOG] Last 60 lines of CoppeliaSim log"

tail -n 60 "$LOG_FILE"

exit $TEST_EXIT_CODE
