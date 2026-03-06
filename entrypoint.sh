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

LOG_FILE=coppeliasim.log
PORT=23000

########################################
# Function to check port
########################################

check_port() {

    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":$PORT"

    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":$PORT"

    elif command -v lsof >/dev/null 2>&1; then
        lsof -i :"$PORT" >/dev/null 2>&1

    else
        echo "[WARN] No port checking tool available"
        return 1
    fi
}

########################################
# Start CoppeliaSim
########################################

echo "[START] Launching CoppeliaSim"

xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
/opt/coppelia/coppeliaSim \
-H \
-s600000 \
-G ZmqRemoteApi.rpcPort=23000 \
-G ZmqRemoteApi.cntPort=23001 \
/app/pick_and_place.ttt > "$LOG_FILE" 2>&1 &

COPPELIA_PID=$!

echo "[INFO] PID: $COPPELIA_PID"
echo "[INFO] Log file: $LOG_FILE"

sleep 5

########################################
# Detect early crash
########################################

if ! kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "ERROR: CoppeliaSim crashed immediately"
    cat "$LOG_FILE"
    exit 1
fi

########################################
# Wait for ZMQ plugin
########################################

echo "[WAIT] Waiting for ZMQ Remote API"

TIMEOUT=180
ELAPSED=0

while true; do

    if grep -iq "zmq" "$LOG_FILE"; then
        echo "[OK] ZMQ plugin detected"
        break
    fi

    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "ERROR: CoppeliaSim crashed during startup"
        tail -n 80 "$LOG_FILE"
        exit 1
    fi

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERROR: ZMQ plugin not detected after $TIMEOUT seconds"
        tail -n 80 "$LOG_FILE"
        kill -TERM $COPPELIA_PID || true
        exit 1
    fi

    sleep 3
    ELAPSED=$((ELAPSED+3))

    echo "[WAIT] ${ELAPSED}s / ${TIMEOUT}s"
    tail -n 4 "$LOG_FILE"

done

########################################
# Wait for port
########################################

echo "[WAIT] Waiting for port $PORT"

PORT_TIMEOUT=120
PORT_ELAPSED=0

while true; do

    if check_port; then
        echo "[OK] Port $PORT is open"
        break
    fi

    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "ERROR: CoppeliaSim crashed before opening port"
        tail -n 80 "$LOG_FILE"
        exit 1
    fi

    if [ $PORT_ELAPSED -ge $PORT_TIMEOUT ]; then
        echo "ERROR: Port $PORT not opened after $PORT_TIMEOUT seconds"
        tail -n 100 "$LOG_FILE"
        kill -TERM $COPPELIA_PID || true
        exit 1
    fi

    sleep 3
    PORT_ELAPSED=$((PORT_ELAPSED+3))

    echo "[WAIT] ${PORT_ELAPSED}s / ${PORT_TIMEOUT}s"
    tail -n 6 "$LOG_FILE"

done

########################################
# Debug tests
########################################

echo "[DEBUG] Checking test folder"

if [ -d /app/tests ]; then
    ls -la /app/tests
else
    echo "[WARN] /app/tests directory not found"
fi

echo "[DEBUG] Python files in project"

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
# Stop CoppeliaSim
########################################

echo "[STOP] Stopping CoppeliaSim"

kill -TERM $COPPELIA_PID 2>/dev/null || true
timeout 10s wait $COPPELIA_PID 2>/dev/null || true

if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "[WARN] Force killing process"
    kill -KILL $COPPELIA_PID 2>/dev/null || true
fi

########################################
# Final logs
########################################

echo "======================================="
echo " Tests finished with code $TEST_EXIT_CODE"
echo "======================================="

echo "[LOG] Last lines of CoppeliaSim log"

tail -n 60 "$LOG_FILE"

exit $TEST_EXIT_CODE
