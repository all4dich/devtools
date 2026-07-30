#!/bin/bash
# serial_log.sh — passively capture every defined UART port in parallel, each to
# its own timestamped log file, until interrupted (Ctrl-C) or an optional
# duration elapses. No command is sent to any port — this is read-only logging.
#
# Usage:
#   serial_log.sh                # capture until Ctrl-C
#   serial_log.sh 30             # capture for 30 seconds, then stop
#
# Env overrides:
#   PORTS     space-separated ports to capture   (default: /dev/ttyUSB0..3)
#   PREFIX    directory for per-port log files    (default: $HOME)
#   BAUD      baud rate                              (default: 115200)
#   DURATION  seconds to capture, 0=until Ctrl-C    (default: 0, or $1)
#
# Each run writes one log per captured port:
#   $PREFIX/serial_<port>_<YYYYmmdd_HHMMSS>.log
# The timestamp is shared across a run and never overwritten, so history is kept.

set -u

PORTS="${PORTS:-/dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3}"
PREFIX="${PREFIX:-$HOME}"
BAUD="${BAUD:-115200}"
DURATION="${DURATION:-${1:-0}}"

# At least one port must exist; absent ports are skipped with a warning (the
# default list is fixed, so not every ttyUSB* is necessarily present).
ACTIVE_PORTS=""
for p in $PORTS; do
    if [ -e "$p" ]; then
        ACTIVE_PORTS="$ACTIVE_PORTS $p"
    else
        echo "warn: $p not found — skipping" >&2
    fi
done
[ -n "$ACTIVE_PORTS" ] || { echo "error: no ports found to capture" >&2; exit 2; }

# One shared timestamp per run so a port's logs sort together and never clobber.
TS="$(date +%Y%m%d_%H%M%S)"
log_path() { echo "$PREFIX/serial_$(basename "$1")_$TS.log"; }

# Cleanup: stop the background readers. Registered as a trap so an early exit
# (Ctrl-C, SIGTERM) tears everything down instead of leaving readers running.
# Idempotent via the CLEANED guard so the normal end-of-run path can also call
# it explicitly.
READERS=""
CLEANED=0
cleanup() {
    [ "$CLEANED" = "1" ] && return
    CLEANED=1
    for pid in $READERS; do kill "$pid" 2>/dev/null; done
    for pid in $READERS; do wait "$pid" 2>/dev/null; done
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

echo "============================ serial logging =============================="
printf '  %-13s %s\n' "PORTS"    "$ACTIVE_PORTS"
printf '  %-13s %s\n' "PREFIX"   "$PREFIX"
printf '  %-13s %s\n' "BAUD"     "$BAUD"
printf '  %-13s %s\n' "DURATION" "$([ "$DURATION" -gt 0 ] && echo "${DURATION}s" || echo "until Ctrl-C")"
echo "---------------------------------------------------------------------------"
for p in $ACTIVE_PORTS; do
    printf '  %-13s %s\n' "log" "$(log_path "$p")"
done
echo "==========================================================================="

# Background readers: one per port, each copying serial -> its own log file,
# unbuffered so logs update in real time. Each reader is exec'd so $! is the
# reader process itself — a single kill reaps it with no orphaned children left.
for p in $ACTIVE_PORTS; do
    lg="$(log_path "$p")"
    : > "$lg"
    ( exec stdbuf -o0 cat "$p" > "$lg" ) &
    READERS="$READERS $!"
done

# Capture until Ctrl-C, or DURATION seconds if a positive duration was given.
if [ "$DURATION" -gt 0 ]; then
    echo "capturing for ${DURATION}s — Ctrl-C to stop early..."
    sleep "$DURATION"
else
    echo "capturing — press Ctrl-C to stop..."
    # Wait on the readers; they run until killed by the trap (Ctrl-C/TERM).
    for pid in $READERS; do wait "$pid" 2>/dev/null; done
fi

# Stop the readers before printing the summary. The EXIT trap also calls this,
# so the trap re-call is a guarded no-op.
cleanup

echo
echo "===== end ====="
echo "logs:"
for p in $ACTIVE_PORTS; do
    printf '  %s\n' "$(log_path "$p")"
done
