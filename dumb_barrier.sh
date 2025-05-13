#!/bin/sh
set -eu

SETUP_FILE=${SYNC_FILE:-/tmp/konduktor/SETUP}
READY_FILE=${READY_FILE:-/tmp/konduktor/READY}
BARRIER_FIFO=${BARRIER_FIFO:-/tmp/konduktor/barrier_fifo}

echo "[gatekeeper] rank=$RANK world=$WORLD_SIZE master=$MASTER_ADDR:$MASTER_PORT"

# --- Server logic ---
server () {
  echo "[server] Starting barrier server"

  mkfifo $BARRIER_FIFO
  socat -u TCP-LISTEN:$MASTER_PORT,reuseaddr,fork OPEN:${BARRIER_FIFO},creat &

  seen=0
  while [ "$seen" -lt $((WORLD_SIZE - 1)) ]; do
    if read line < $BARRIER_FIFO; then
      echo "[server] Got rank $line"
      seen=$((seen + 1))
    fi
  done

  echo "[server] All peers arrived"

  # Broadcast GO to all peers
  i=1
  while [ "$i" -lt "$WORLD_SIZE" ]; do
    echo "GO" | socat - TCP:$MASTER_ADDR:$MASTER_PORT
    i=$((i + 1))
  done

  touch "$READY_FILE"
  trap : TERM INT; sleep infinity & wait
}

# --- Client logic ---
client () {

  echo "[client] waiting for setup to finish"

  while [ ! -f "${SETUP_FILE}" ]; do
    sleep 0.5
  done

  echo "[client] Sending rank to server"
  echo "$RANK" | socat - TCP:$MASTER_ADDR:$MASTER_PORT

  # Wait for GO signal
  while true; do
    if socat - TCP:$MASTER_ADDR:$MASTER_PORT | grep -q "^GO$"; then
      echo "[client] Got GO"
      touch "$READY_FILE"
      return
    fi
    sleep 1
  done
  trap : TERM INT; sleep infinity & wait
}

if [ "$RANK" = "0" ]; then
  server
else
  client
fi
