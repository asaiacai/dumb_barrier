#!/bin/sh
set -u

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
  echo "[server] opening GO listener on $GO_PORT"
  # any client that now connects reads “GO” then the socket closes
  ( printf 'GO\n' | socat -u - TCP-LISTEN:${GO_PORT},reuseaddr,fork ) &

  touch "$READY_FILE"
  trap : TERM INT; sleep infinity & wait
}

# --- Client logic ---
client () {
  echo "[client] waiting for setup to finish"

  while [ ! -f "${SETUP_FILE}" ]; do
    sleep 0.5
  done

  echo "[client] Waiting for GO from master …"
  while true; do
    #––– ping the master with our rank –––#
    echo "[client] Sending rank to server"
    echo "$RANK" | socat - TCP:$MASTER_ADDR:$MASTER_PORT,connect-timeout=2
  
    #––– immediately check whether GO is ready –––#
    if socat -u TCP:${MASTER_ADDR}:${GO_PORT},connect-timeout=2 - | grep -q '^GO$'; then
      echo "[client] received GO"
      break
    fi
  
    #––– wait a moment before the next attempt –––#
    sleep 1
  done

  touch "$READY_FILE"
  trap : TERM INT; sleep infinity & wait
}

if [ "$RANK" = "0" ]; then
  server
else
  client
fi
