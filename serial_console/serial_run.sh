#!/bin/bash
# serial_run.sh — open a serial port, send one command, print output to stdout,
# exit when the device's prompt reappears (= command actually finished).
#
# Usage:
#   serial_run.sh "<command>"
#
# Env overrides:
#   PORT     serial device                          (default: /dev/ttyUSB0)
#   BAUD     baud rate                              (default: 115200)
#   PROMPT        shell prompt to wait for          (default: REBELLIONS$)
#   IDLE_TIMEOUT  abort if no new bytes for N sec   (default: 30)
#   MAX_TIMEOUT   absolute max total wait, 0=off    (default: 0)
#   TAIL_S        grace period after prompt seen    (default: 0.5)
#   WAKE     send blank CR before command           (default: 1 = yes)

set -u

if [ $# -lt 1 ]; then
    echo "usage: $0 \"<command to run on serial console>\"" >&2
    exit 1
fi

CMD="$*"
PORT="${PORT:-/dev/ttyUSB0}"
BAUD="${BAUD:-115200}"
PROMPT="${PROMPT:-REBELLIONS$ }"
IDLE_TIMEOUT="${IDLE_TIMEOUT:-30}"
MAX_TIMEOUT="${MAX_TIMEOUT:-0}"
TAIL_S="${TAIL_S:-0.5}"
WAKE="${WAKE:-1}"
EOL="${EOL:-cr}"          # cr | lf | crlf
DEBUG="${DEBUG:-0}"
TYPE_DELAY="${TYPE_DELAY:-0.05}"   # seconds between characters when sending
WAKE_GAP="${WAKE_GAP:-1.0}"        # seconds to wait between wake CR and command

case "$EOL" in
    cr)   END=$'\r' ;;
    lf)   END=$'\n' ;;
    crlf) END=$'\r\n' ;;
    *)    echo "error: EOL must be cr|lf|crlf" >&2; exit 1 ;;
esac

[ -e "$PORT" ] || { echo "error: $PORT not found" >&2; exit 2; }

# Configure serial line: 8N1, raw, no echo / no flow control munging.
stty -F "$PORT" "$BAUD" cs8 -cstopb -parenb \
    raw -echo -echoe -echok -echoctl -echoke \
    -icrnl -inlcr -igncr -ixon -ixoff \
    || { echo "error: stty failed on $PORT" >&2; exit 3; }

echo ">>> $PORT @ $BAUD — sending: $CMD"

# Internal temp buffer used only for prompt detection (not a user-facing log).
BUF=$(mktemp -t serial_run.XXXXXX)

# Cleanup must signal the WHOLE reader process group, not just the subshell —
# otherwise the inner cat/tee inherit fd 9 and keep /dev/ttyUSB0 held open
# after the script exits.
READER=""
cleanup() {
    if [ -n "$READER" ]; then
        kill -TERM -- -"$READER" 2>/dev/null
        wait "$READER" 2>/dev/null
        READER=""
    fi
    exec 9<&- 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    [ -n "${BUF:-}" ] && rm -f "$BUF"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# Open port on fd 9 (read/write).
exec 9<>"$PORT"

# Background reader: copy serial -> stdout + prompt-detection buffer, unbuffered
# so stdout shows output in real time and our prompt poller can see new bytes
# immediately. `set -m` puts the pipeline in its own process group so cleanup
# can take down cat and tee together (otherwise they'd outlive the subshell
# and keep the serial port pinned).
set -m
( stdbuf -o0 cat <&9 | stdbuf -o0 tee -a "$BUF" ) &
READER=$!
set +m

# Give the reader a moment, then optionally wake the prompt.
sleep 0.3
if [ "$WAKE" = "1" ]; then
    printf '%s' "$END" >&9
    sleep "$WAKE_GAP"
fi

# Snapshot the buffer size right before sending the command so we only look for
# the prompt in bytes that arrive AFTER this point (not the wake's prompt).
SIZE_BEFORE_CMD=$(stat -c %s "$BUF")

# Send the command one byte at a time with TYPE_DELAY between bytes,
# so devices with slow UART handlers don't drop characters.
i=0
while [ $i -lt ${#CMD} ]; do
    printf '%s' "${CMD:$i:1}" >&9
    sleep "$TYPE_DELAY"
    i=$((i + 1))
done
printf '%s' "$END" >&9

# Wait for the prompt to reappear — that means the command finished.
# Idle-timeout based: only give up if the buffer stops growing for IDLE_TIMEOUT
# seconds. While the device is still printing, keep waiting.
START_TS=$(date +%s)
LAST_GROW_TS=$START_TS
LAST_SIZE=$(stat -c %s "$BUF")
FINISHED=0
ABORT_REASON=""
while :; do
    NOW_TS=$(date +%s)

    CURR_SIZE=$(stat -c %s "$BUF")
    if [ "$CURR_SIZE" != "$LAST_SIZE" ]; then
        LAST_SIZE=$CURR_SIZE
        LAST_GROW_TS=$NOW_TS
    fi

    if dd if="$BUF" bs=1 skip="$SIZE_BEFORE_CMD" status=none 2>/dev/null \
            | grep -qF -- "$PROMPT"; then
        sleep "$TAIL_S"
        FINISHED=1
        break
    fi

    if [ $((NOW_TS - LAST_GROW_TS)) -ge "$IDLE_TIMEOUT" ]; then
        ABORT_REASON="no new bytes for ${IDLE_TIMEOUT}s"
        break
    fi
    if [ "$MAX_TIMEOUT" -gt 0 ] && [ $((NOW_TS - START_TS)) -ge "$MAX_TIMEOUT" ]; then
        ABORT_REASON="max wall-clock ${MAX_TIMEOUT}s reached"
        break
    fi

    sleep 0.1
done

# Stop the reader (and its cat/tee children via the process group) and close
# the port. The EXIT trap also runs cleanup in case anything below fails.
cleanup

echo
if [ "$FINISHED" = "1" ]; then
    echo "===== end ====="
else
    echo "===== timeout: $ABORT_REASON — prompt '$PROMPT' not seen =====" >&2
fi
