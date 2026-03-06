#!/bin/bash
set -e

echo "======================================="
echo " CoppeliaSim CI Runtime"
echo "======================================="

mkdir -p output
LOG_FILE=coppeliasim.log
PORT=23000

echo "[INIT] Initializing runtime environment"
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR

echo "[START] Launching CoppeliaSim (headless)"
xvfb-run --auto-servernum \
/opt/coppelia/coppeliaSim \
-H \                     # true headless
-s \                     # start simulation continuously
-G ZmqRemoteApi.rpcPort=23000 \
-G ZmqRemoteApi.cntPort=23001 \
-a /app/start_zmq.lua \   # your Lua add-on to start ZMQ
-f /app/pick_and_place.ttt > $LOG_FILE 2>&1 &

COPSIM_PID=$!
echo "[INFO] PID: $COPSIM_PID"
echo "[INFO] Log file: $LOG_FILE"

# Wait until ZMQ server is ready
TIMEOUT=60
ELAPSED=0
echo "[WAIT] Waiting for ZMQ RemoteAPI server..."
while ! grep -q "ZeroMQ remote API server add-on initialisé" $LOG_FILE; do
    sleep 2
    ELAPSED=$((ELAPSED+2))
    echo "  waiting... ${ELAPSED}s"
    tail -n 6 $LOG_FILE
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "[ERROR] ZMQ RemoteAPI server did not start in time"
        tail -n 60 $LOG_FILE
        kill -TERM $COPSIM_PID || true
        exit 1
    fi
done
echo "[OK] ZMQ RemoteAPI server is ready!"

# Run pytest
echo "[TEST] Running pytest"
export PYTHONPATH=/app
pytest tests/ \
    --html=output/report.html \
    --self-contained-html \
    --timeout=300 \
    --timeout-method=thread \
    -vv

TEST_EXIT_CODE=$?

# Stop CoppeliaSim
echo "[STOP] Stopping CoppeliaSim"
kill -TERM $COPSIM_PID || true
timeout 12s wait $COPSIM_PID || true
if kill -0 $COPSIM_PID 2>/dev/null; then
    echo "CoppeliaSim still running → force kill"
    kill -KILL $COPSIM_PID || true
fi

echo "[DONE] Test finished with exit code $TEST_EXIT_CODE"
tail -n 50 $LOG_FILE
exit $TEST_EXIT_CODE
