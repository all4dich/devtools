#!/bin/bash
# serial_run.sh — send one command to a target serial console while capturing
# every defined port in parallel, each to its own timestamped log file, and exit
# when the target device's prompt reappears (= command actually finished).
#
# The command is sent to exactly ONE port (PORT). Every port in PORTS is opened
# for reading at the same time — a command on one console can produce side-effect
# output on the others — and each port's incoming text is written to its own log.
#
# Usage:
#   serial_run.sh "<command>"
#
# Env overrides:
#   PORTS    space-separated ports to capture   (default: /dev/ttyUSB0..3)
#   PORT     target port the command is sent to (default: first of PORTS)
#   PREFIX   directory for per-port log files    (default: $HOME)
#   BAUD     baud rate                              (default: 115200)
#   PROMPT        shell prompt to wait for          (default: REBELLIONS$)
#   IDLE_TIMEOUT  abort if no new bytes for N sec   (default: 30)
#   MAX_TIMEOUT   absolute max total wait, 0=off    (default: 0)
#   TAIL_S        grace period after prompt seen    (default: 0.5)
#   WAKE     send blank CR before command           (default: 1 = yes)
#
# Each run writes one log per captured port:
#   $PREFIX/serial_<port>_<YYYYmmdd_HHMMSS>.log
# The timestamp is shared across a run and never overwritten, so history is kept.

set -u

if [ $# -lt 1 ]; then
    echo "usage: $0 \"<command to run on serial console>\"" >&2
    exit 1
fi

CMD="$*"
PORTS="${PORTS:-/dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3}"
PORT="${PORT:-${PORTS%% *}}"    # target defaults to the first port in PORTS
PREFIX="${PREFIX:-$HOME}"
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

# Make sure the target port is part of the captured set.
case " $PORTS " in
    *" $PORT "*) ;;
    *) PORTS="$PORT $PORTS" ;;
esac

# The target port must exist; other ports are skipped with a warning if absent
# (the default list is fixed, so not every ttyUSB* is necessarily present).
[ -e "$PORT" ] || { echo "error: target $PORT not found" >&2; exit 2; }
ACTIVE_PORTS=""
for p in $PORTS; do
    if [ -e "$p" ]; then
        ACTIVE_PORTS="$ACTIVE_PORTS $p"
    else
        echo "warn: $p not found — skipping" >&2
    fi
done

# One shared timestamp per run so a port's logs sort together and never clobber.
TS="$(date +%Y%m%d_%H%M%S)"
log_path() { echo "$PREFIX/serial_$(basename "$1")_$TS.log"; }
TARGET_LOG="$(log_path "$PORT")"

# Cleanup: stop the background readers and close the target port. Registered as
# a trap so an early exit (stty failure, Ctrl-C, SIGTERM) tears everything down
# instead of leaving readers running and the port held open. Idempotent via the
# CLEANED guard so the normal end-of-run path can also call it explicitly.
READERS=""
PORT_OPEN=0
CLEANED=0
cleanup() {
    [ "$CLEANED" = "1" ] && return
    CLEANED=1
    for pid in $READERS; do kill "$pid" 2>/dev/null; done
    for pid in $READERS; do wait "$pid" 2>/dev/null; done
    if [ "$PORT_OPEN" = "1" ]; then
        exec 9<&- 9>&-
        PORT_OPEN=0
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Configure every captured line: 8N1, raw, no echo / no flow control munging.
for p in $ACTIVE_PORTS; do
    stty -F "$p" "$BAUD" cs8 -cstopb -parenb \
        raw -echo -echoe -echok -echoctl -echoke \
        -icrnl -inlcr -igncr -ixon -ixoff \
        || { echo "error: stty failed on $p" >&2; exit 3; }
done

echo "============================ serial connection ============================"
printf '  %-13s %s\n' "PORTS"        "$ACTIVE_PORTS"
printf '  %-13s %s\n' "PORT"         "$PORT (target)"
printf '  %-13s %s\n' "PREFIX"       "$PREFIX"
printf '  %-13s %s\n' "BAUD"         "$BAUD"
printf '  %-13s %s\n' "PROMPT"       "$PROMPT"
printf '  %-13s %s\n' "EOL"          "$EOL"
printf '  %-13s %s\n' "IDLE_TIMEOUT" "${IDLE_TIMEOUT}s"
printf '  %-13s %s\n' "MAX_TIMEOUT"  "$([ "$MAX_TIMEOUT" -gt 0 ] && echo "${MAX_TIMEOUT}s" || echo "off")"
printf '  %-13s %s\n' "TAIL_S"       "${TAIL_S}s"
printf '  %-13s %s\n' "WAKE"         "$([ "$WAKE" = "1" ] && echo "yes" || echo "no")"
printf '  %-13s %s\n' "TYPE_DELAY"   "${TYPE_DELAY}s"
printf '  %-13s %s\n' "WAKE_GAP"     "${WAKE_GAP}s"
printf '  %-13s %s\n' "DEBUG"        "$([ "$DEBUG" = "1" ] && echo "on" || echo "off")"
echo "---------------------------------------------------------------------------"
for p in $ACTIVE_PORTS; do
    printf '  %-13s %s\n' "log" "$(log_path "$p")"
done
echo "---------------------------------------------------------------------------"
printf '  %-13s %s\n' "command"      "$CMD"
echo "==========================================================================="

# Background readers: one per port, each copying serial -> its own log file,
# unbuffered so logs update in real time and our prompt poller sees new bytes
# immediately. Each reader is exec'd so $! is the reader process itself — a
# single kill reaps it with no orphaned children left holding our stdout. The
# target port is opened read/write on fd 9 (so we can send the command) and its
# reader also mirrors to stdout so the run is visible live; the other ports are
# captured read-only and silently.
exec 9<>"$PORT"
PORT_OPEN=1
: > "$TARGET_LOG"
( exec stdbuf -o0 tee -a "$TARGET_LOG" <&9 ) &
READERS="$!"
for p in $ACTIVE_PORTS; do
    [ "$p" = "$PORT" ] && continue
    lg="$(log_path "$p")"
    : > "$lg"
    ( exec stdbuf -o0 cat "$p" > "$lg" ) &
    READERS="$READERS $!"
done

# Give the readers a moment, then optionally wake the target prompt.
sleep 0.3
if [ "$WAKE" = "1" ]; then
    printf '%s' "$END" >&9
    sleep "$WAKE_GAP"
fi

# Snapshot the target log size right before sending the command so we only look
# for the prompt in bytes that arrive AFTER this point (not the wake's prompt).
SIZE_BEFORE_CMD=$(stat -c %s "$TARGET_LOG")

# Send the command one byte at a time with TYPE_DELAY between bytes,
# so devices with slow UART handlers don't drop characters.
i=0
while [ $i -lt ${#CMD} ]; do
    printf '%s' "${CMD:$i:1}" >&9
    sleep "$TYPE_DELAY"
    i=$((i + 1))
done
printf '%s' "$END" >&9

# Wait for the prompt to reappear on the target — that means the command
# finished. Idle-timeout based: only give up if the target log stops growing for
# IDLE_TIMEOUT seconds. While the device is still printing, keep waiting.
START_TS=$(date +%s)
LAST_GROW_TS=$START_TS
LAST_SIZE=$(stat -c %s "$TARGET_LOG")
FINISHED=0
ABORT_REASON=""
while :; do
    NOW_TS=$(date +%s)

    CURR_SIZE=$(stat -c %s "$TARGET_LOG")
    if [ "$CURR_SIZE" != "$LAST_SIZE" ]; then
        LAST_SIZE=$CURR_SIZE
        LAST_GROW_TS=$NOW_TS
    fi

    if dd if="$TARGET_LOG" bs=1 skip="$SIZE_BEFORE_CMD" status=none 2>/dev/null \
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

# Stop all readers and close the target port. The EXIT trap also calls this, so
# this explicit call just ensures the readers stop before we print the summary
# (the target reader mirrors to stdout); the trap re-call is a guarded no-op.
cleanup

echo
if [ "$FINISHED" = "1" ]; then
    echo "===== end ====="
else
    echo "===== timeout: $ABORT_REASON — prompt '$PROMPT' not seen =====" >&2
fi
echo "logs:"
for p in $ACTIVE_PORTS; do
    printf '  %s\n' "$(log_path "$p")"
done

if [ "$DEBUG" = "1" ]; then
    echo
    echo "===== hex dump of target captured output ====="
    xxd "$TARGET_LOG"
    echo "===== end hex ====="
fi
