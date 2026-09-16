#!/bin/bash
# serial_run.sh — send one command to a UART console and save what it prints.
#
# The command is typed on the port one character at a time (these consoles drop
# input that arrives too fast), preceded by a bare CR to wake the prompt. The
# reply is streamed to the screen and appended to a log file until the console
# prints its completion marker ('-> FINISHED' by default) or the timeout runs
# out. The command line, port and result (finished / timed out) are recorded in
# the same log, so the file stands on its own.
#
# Usage:
#   serial_run.sh replay_ver                      # on /dev/ttyUSB0, log to $HOME
#   serial_run.sh -p /dev/ttyUSB2 replay_ver      # another port
#   serial_run.sh -t 60 run_test 3                # allow 60s; args are joined
#                                                 # with spaces: 'run_test 3'
#   serial_run.sh -o run.log cmd_a; serial_run.sh -o run.log cmd_b
#                                                 # both replies in one file
#   serial_run.sh -q -o out.log replay_ver        # log only, nothing on screen
#   serial_run.sh -w replay_ver                   # -w = no completion marker,
#                                                 # capture for the whole timeout
#
# Exit status:
#   0    the console printed the completion marker
#   124  the marker did not arrive within the timeout (output is still logged)
#   130  interrupted with Ctrl-C (whatever arrived so far is logged)
#   2    bad usage
#   3    the port could not be opened or configured
#
# Env overrides (the matching flag wins when both are given):
#   PORT       UART device                        (default: /dev/ttyUSB0)   -p
#   BAUD       baud rate                          (default: 115200)         -b
#   TIMEOUT    seconds to wait for the marker     (default: 30)             -t
#   LOG        log file, appended to; empty = default name below            -o
#   PREFIX     directory for the default log file (default: $HOME)
#   DONE_RE    case-insensitive ERE that ends the capture; empty = wait the
#              full TIMEOUT                       (default: FINISHED)       -w
#   QUIET      1=do not echo the reply on screen  (default: 0)              -q
#   TYPE_DELAY seconds between typed characters   (default: 0.05)
#   WAKE_GAP   seconds between wake CR and command (default: 1.0)
#
# Default log file (kept, never overwritten — one per run):
#   $PREFIX/serial_run_<port>_<YYYYmmdd_HHMMSS>.log

set -u

usage() {
    cat >&2 <<USAGE
usage: $(basename "$0") [-p PORT] [-b BAUD] [-t SECONDS] [-o LOGFILE] [-q] [-w] COMMAND [ARG...]

  -p PORT     UART device (default: /dev/ttyUSB0)
  -b BAUD     baud rate (default: 115200)
  -t SECONDS  give up waiting for the completion marker after this long
              (default: 30)
  -o LOGFILE  append the run to this file instead of a new timestamped file
              under \$PREFIX (default: \$HOME/serial_run_<port>_<timestamp>.log)
  -q          quiet: write the reply to the log only, not to the screen
  -w          wait the whole timeout instead of stopping at the completion
              marker ('-> FINISHED'); for commands that never print one
  COMMAND...  the console command; several words are joined with spaces
USAGE
    exit 2
}

PORT="${PORT:-/dev/ttyUSB0}"
BAUD="${BAUD:-115200}"
TIMEOUT="${TIMEOUT:-30}"
LOG="${LOG:-}"
PREFIX="${PREFIX:-$HOME}"
DONE_RE="${DONE_RE-FINISHED}"
QUIET="${QUIET:-0}"
TYPE_DELAY="${TYPE_DELAY:-0.05}"
WAKE_GAP="${WAKE_GAP:-1.0}"

while getopts ':p:b:t:o:qwh' opt; do
    case "$opt" in
        p) PORT="$OPTARG" ;;
        b) BAUD="$OPTARG" ;;
        t) TIMEOUT="$OPTARG" ;;
        o) LOG="$OPTARG" ;;
        q) QUIET=1 ;;
        w) DONE_RE="" ;;
        h) usage ;;
        :) echo "error: -$OPTARG needs a value" >&2; usage ;;
        *) echo "error: unknown option -$OPTARG" >&2; usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "error: no command given" >&2; usage ;}
CMD="$*"

case "$TIMEOUT" in
    ''|*[!0-9.]*) echo "error: -t needs a number of seconds, got '$TIMEOUT'" >&2; exit 2 ;;
esac
for tool in timeout stdbuf stty; do
    command -v "$tool" >/dev/null 2>&1 \
        || { echo "error: '$tool' is required (coreutils)" >&2; exit 3; }
done

TS="$(date +%Y%m%d_%H%M%S)"
[ -n "$LOG" ] || LOG="$PREFIX/serial_run_$(basename "$PORT")_$TS.log"
mkdir -p "$(dirname -- "$LOG")" 2>/dev/null
: >> "$LOG" || { echo "error: cannot write $LOG" >&2; exit 3; }

# Port: 8N1, raw, no echo, no CR/LF translation, no flow-control munging.
[ -e "$PORT" ] || { echo "error: $PORT not found" >&2; exit 3; }
stty -F "$PORT" "$BAUD" cs8 -cstopb -parenb \
    raw -echo -echoe -echok -echoctl -echoke \
    -icrnl -inlcr -igncr -ixon -ixoff \
    || { echo "error: stty failed on $PORT" >&2; exit 3; }
# Check the port opens read/write in a subshell first: a failed redirection on
# `exec` would kill this (non-interactive) shell outright.
( : <>"$PORT" ) 2>/dev/null || { echo "error: cannot open $PORT" >&2; exit 3; }

RAW="$(mktemp)"
READER=""
VIEWER=""
START=""
LOGGED=0

elapsed() { awk -v a="$START" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }'; }

# Append the captured reply and the result line to the log. NULs and CRs are
# framing noise from these consoles, not content, so the log is plain
# LF-terminated text. The result line always starts on its own line, even if
# the console did not end its output with a newline ($(...) strips a trailing
# LF, so the test is empty both for an empty reply and for one ending in LF).
write_log() {
    local result="$1"
    tr -d '\000\r' < "$RAW" >> "$LOG"
    [ -n "$(tr -d '\000\r' < "$RAW" | tail -c1)" ] && echo >> "$LOG"
    echo "# result: $result after $(elapsed)s" >> "$LOG"
    LOGGED=1
}

cleanup() {
    [ -n "$READER" ] && kill "$READER" 2>/dev/null
    [ -n "$VIEWER" ] && kill "$VIEWER" 2>/dev/null
    wait 2>/dev/null
    # Ctrl-C / kill before the normal end: keep what did arrive, and say so.
    if [ "$LOGGED" = "0" ] && [ -n "$START" ]; then
        write_log "interrupted"
        echo "interrupted — partial output kept in $LOG" >&2
    fi
    rm -f "$RAW"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

{
    echo "# ==== serial_run.sh  $(date '+%Y-%m-%d %H:%M:%S')  port=$PORT baud=$BAUD timeout=${TIMEOUT}s"
    echo "# command: $CMD"
} >> "$LOG"
if [ "$QUIET" != "1" ]; then
    echo "port:    $PORT @ $BAUD"
    echo "command: $CMD"
    echo "log:     $LOG"
    echo "-------------------------------------------------------------------"
fi

exec 8<>"$PORT"
# Reader: everything the console sends goes to $RAW, byte for byte, until the
# timeout. A single process on purpose: killing 'timeout' also ends 'cat' (it
# forwards the signal), and 'wait' on a pipeline would block for the whole job.
timeout "$TIMEOUT" stdbuf -o0 cat <&8 >> "$RAW" &
READER=$!
if [ "$QUIET" != "1" ]; then
    # Live view of the raw bytes; the terminal copes with CRLF and NULs itself.
    tail -n +1 -s 0.1 -f --pid="$READER" "$RAW" &
    VIEWER=$!
fi

START=$(date +%s.%N)
sleep 0.3
printf '\r' >&8                        # wake the prompt
sleep "$WAKE_GAP"
i=0
while [ $i -lt ${#CMD} ]; do
    printf '%s' "${CMD:$i:1}" >&8
    sleep "$TYPE_DELAY"
    i=$((i + 1))
done
printf '\r' >&8

# Wait for the completion marker (or for the reader's timeout). The device's
# echo of the command line is ignored so a marker-like word in the command
# itself does not count.
RESULT="timeout"
while kill -0 "$READER" 2>/dev/null; do
    if [ -n "$DONE_RE" ] && grep -vF -- "$CMD" "$RAW" | grep -qiE -- "$DONE_RE"; then
        RESULT="finished"
        kill "$READER" 2>/dev/null
        break
    fi
    sleep 0.1
done
wait "$READER" 2>/dev/null
[ -n "$VIEWER" ] && wait "$VIEWER" 2>/dev/null
VIEWER=""
READER=""
exec 8<&- 8>&-
sleep 0.2                                # let the viewer flush its last line
[ -n "$DONE_RE" ] || RESULT="captured"

ELAPSED="$(elapsed)"
write_log "$RESULT"

if [ "$QUIET" != "1" ]; then
    echo "-------------------------------------------------------------------"
    echo "result:  $RESULT after ${ELAPSED}s"
    echo "log:     $LOG"
fi

case "$RESULT" in
    finished|captured) exit 0 ;;
    *) echo "warn: no '$DONE_RE' within ${TIMEOUT}s on $PORT" >&2; exit 124 ;;
esac
