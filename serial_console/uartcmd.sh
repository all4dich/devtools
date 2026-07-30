#!/bin/bash
# Usage: uartcmd.sh "<command>" [wait_seconds]
PORT=/dev/ttyUSB0
CMD="$1"
WAIT="${2:-3}"
stty -F "$PORT" 115200 cs8 -cstopb -parenb -ixon -ixoff raw -echo 2>/dev/null
timeout "$WAIT" cat "$PORT" > /tmp/_uart_resp.txt 2>/dev/null &
READER=$!
sleep 0.3
printf '%s\r' "$CMD" > "$PORT"
wait $READER 2>/dev/null
cat -v /tmp/_uart_resp.txt
