#!/bin/bash
# serial_log.sh — capture every target UART port in parallel, each to its own
# timestamped log file, until interrupted (Ctrl-C) or an optional duration
# elapses. Capture itself is read-only; the only bytes this script ever writes
# are the detection probe (see PROBE below), which runs before capture starts.
#
# Port detection: each /dev/ttyUSB* is probed with $PROBE_CMD (default
# 'replay_ver') and only the ports that actually answer it become PORTS. If no
# port answers — or PORTS is set explicitly in the environment, or PROBE=0 —
# the fixed default list is used instead.
#
# Once the capture is up, one test from tc/scripts is run — run_basic_test.sh
# unless '-c NAME' picks another. tc/scripts is located from this file's own
# path, so the run behaves the same from any working directory. What the test
# prints is saved to host.log next to its app.log, and both are rotated first,
# so each pair of files belongs to a single test run.
#
# Usage:
#   serial_log.sh                        # capture, then run run_basic_test.sh
#   serial_log.sh -c run_stress_test.sh  # ... run that test from tc/scripts
#   serial_log.sh -s -m                  # end when the test does, then mail —
#                                        # nothing to press, good for cron
#   serial_log.sh 30                     # capture for 30 seconds, then stop
#   serial_log.sh -l horizontal          # viewer panes side by side in a row
#   serial_log.sh -l vertical 30         # stacked panes (default), 30s capture
#   serial_log.sh -m 3600                # 1h capture, mail the summary at the
#                                        # end as well as on Ctrl-C
#
# Required environment (the tests need both; the run stops at once without them):
#   BASE_PATH    test-vector root, e.g. /mnt/archive/vdk_data/<release>
#   OUTPUT_PATH  directory the tests write their results to
#
# Env overrides:
#   PORTS      space-separated ports to capture; set = skip detection
#                                                  (default: detected, else
#                                                   /dev/ttyUSB0..3)
#   PREFIX     directory for per-port log files     (default: $HOME)
#   BAUD       baud rate                            (default: 115200)
#   DURATION   seconds to capture, 0=until Ctrl-C   (default: 0, or $1)
#   SKIP_WAIT  1=stop as soon as the test script returns, waiting for neither
#              Ctrl-C nor $DURATION; same as -s              (default: 0)
#   TEST_SCRIPT  the test to run once the capture is up, as a name from
#              tc/scripts ('.sh' optional) or a path if it contains a '/'; same
#              as -c                            (default: run_basic_test.sh)
#   TC_SCRIPTS_DIR  where a bare TEST_SCRIPT name is looked up; found from this
#              script's own location, so the run works from any directory
#                                        (default: <dir of this file>/../tc/scripts)
#   APP_LOG    the test's own log (written by rbln_exec_tc.py relative to its
#              working directory). It is rotated to app_<its mtime>.log as this
#              capture starts, so the log the next test writes holds that test
#              only; empty = leave it alone         (default: $PWD/app.log)
#   HOST_LOG   everything the test script prints, saved as it also goes to the
#              screen; rotated to host_<its mtime>.log the same way, and kept
#              next to app.log; empty = screen only
#                                        (default: <dir of $APP_LOG>/host.log)
#   PROBE      1=detect ports, 0=use PORTS as-is    (default: 1)
#   PROBE_CMD  command a usable port must answer    (default: replay_ver)
#   PROBE_WAIT seconds to wait for the answer       (default: 3)
#   PROBE_ERR_RE  case-insensitive ERE that marks a reply as "not supported"
#                                     (default: unknown|invalid|not found|...)
#   PROBE_OK_RE   case-insensitive ERE the reply must contain; these consoles
#                 print '-> FINISHED' when a command completes, so that is the
#                 detection signal. Set empty to accept any non-echo reply.
#                                                     (default: FINISHED)
#   PROMPT     console prompt, stripped from replies   (default: REBELLIONS$ )
#   TYPE_DELAY seconds between probe characters     (default: 0.05)
#   WAKE_GAP   seconds between wake CR and probe    (default: 1.0)
#   TMUX_VIEW  1=open the tmux log viewer, 0=off    (default: 1)
#   TMUX_SESSION  viewer session name            (default: serial_log_<TS>)
#   TMUX_VIEW_KILL  1=kill the viewer when the run ends, 0=leave it up
#                                                   (default: 0)
#   TMUX_LAYOUT  pane arrangement, same values as -l   (default: vertical)
#
# Email when the run ends: interrupting the capture with Ctrl-C sends a summary
# mail (ports, durations, log paths, the tail of each log) over SMTP, with every
# log this run produced attached — each captured port's log plus the test's
# app.log and host.log — gzipped, and capped by MAIL_ATTACH_MAX_KB. app.log and
# host.log are attached under a name carrying the run timestamp, so two runs'
# attachments never look alike in one thread. With -m the same mail is also sent
# when the capture ends on its own. This is entirely optional — if SMTP_HOST,
# SMTP_USER or SMTP_PASS is missing (or curl is not installed), the mail step is
# skipped with a note and the run ends normally. Nothing else about the capture
# depends on it. Asking for it with -m and not having the credentials set is
# worth hearing about early, so that combination warns at startup as well.
#   SMTP_HOST  SMTP server host; unset = no mail            (default: unset)
#   SMTP_USER  SMTP username; unset = no mail               (default: unset)
#   SMTP_PASS  SMTP password / app token; unset = no mail   (default: unset)
#   SMTP_PORT  SMTP port                                    (default: 587)
#   SMTP_TLS   auto|starttls|ssl|none — 'auto' picks ssl on port 465,
#              starttls elsewhere                           (default: auto)
#   SMTP_AUTH  auto|none|plain|login|cram-md5|... — 'auto' lets curl pick the
#              mechanism; 'none' sends without logging in (internal relays) and
#              then SMTP_USER/SMTP_PASS are not required     (default: auto)
#   MAIL_TO    recipients, comma- or space-separated      (default: $SMTP_USER)
#   MAIL_FROM  envelope/From address                      (default: $SMTP_USER)
#   MAIL_ON_INT  1=mail when Ctrl-C stops the run, 0=never  (default: 1)
#   MAIL_ON_END  1=also mail when the capture ends on its own; same as -m
#                                                            (default: 0)
#   MAIL_TAIL_LINES  log lines to quote per port in the mail  (default: 20)
#   MAIL_DEBUG  1=print the whole SMTP conversation on send  (default: 0)
#   MAIL_ATTACH  1=attach the full log files, 0=summary only  (default: 1)
#   MAIL_ATTACH_GZIP  1=gzip each attached log, 0=send as-is  (default: 1)
#   MAIL_ATTACH_MAX_KB  total attachment budget in KB after compression;
#              logs past it are named in the body but not attached, 0=no cap
#                                                        (default: 10240 = 10MB)
#   MAIL_TIMEOUT  seconds curl may spend delivering        (default: 120)
#
# Example (Gmail-style submission port, app password):
#   SMTP_HOST=smtp.gmail.com SMTP_PORT=587 SMTP_USER=you@rebellions.ai \
#   SMTP_PASS=xxxx MAIL_TO=you@rebellions.ai serial_log.sh
#
# Viewer: a detached tmux session is created once the log files exist, with one
# 'tail -F' pane per log — stacked in one column ('-l vertical', the default) or
# side by side in one row ('-l horizontal'). It is not attached, so the capture
# runs in the background either way:
#   tmux attach -t serial_log_<YYYYmmdd_HHMMSS>    # watch all logs live
#   tmux kill-session -t serial_log_<...>          # close the viewer
#
# Each run writes one log per captured port:
#   $PREFIX/serial_<port>_<YYYYmmdd_HHMMSS>.log
# The timestamp is shared across a run and never overwritten, so history is kept.

set -u

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") [-c test_script] [-s] [-l vertical|horizontal] [-m]
                       [duration_seconds]

  -c SCRIPT   which test to run once the capture is up: a name from tc/scripts,
              with '.sh' optional (default: run_basic_test.sh). A name with a
              '/' in it is used as a path instead
  -l LAYOUT   arrange the viewer's panes: 'vertical' stacks them in one column,
              'horizontal' puts them side by side in one row (default: vertical)
  -m          also mail the run summary when the capture ends on its own
              (duration elapsed); without it only Ctrl-C sends mail
  -s          skip the wait at the end: the run stops as soon as the test
              script returns, instead of waiting for Ctrl-C (or a duration)
  duration    seconds to capture; omitted or 0 = until Ctrl-C. Ignored with -s

BASE_PATH and OUTPUT_PATH must be set in the environment — the tests need both,
so the run stops immediately if either is missing.

Mail needs SMTP_HOST, SMTP_USER and SMTP_PASS; if any is missing the mail step
is skipped and the capture is unaffected. With -m the missing ones are named up
front, so a long run doesn't end in a mail that was never going to be sent.

See the header of this script for the full list of env overrides.
EOF
}

# -l overrides $TMUX_LAYOUT, -m overrides $MAIL_ON_END, -c overrides $TEST_SCRIPT
# and -s overrides $SKIP_WAIT; parsed before the positional duration is read so
# 'serial_log.sh -c run_stress_test.sh -m -s' works.
TMUX_LAYOUT="${TMUX_LAYOUT:-vertical}"
MAIL_ON_END="${MAIL_ON_END:-0}"
TEST_SCRIPT="${TEST_SCRIPT:-run_basic_test.sh}"
SKIP_WAIT="${SKIP_WAIT:-0}"
MAIL_ON_END_OPT=0   # 1 only when -m was actually passed, not MAIL_ON_END=1
while getopts ":l:c:msh" opt; do
    case "$opt" in
        l)  TMUX_LAYOUT="$OPTARG" ;;
        c)  TEST_SCRIPT="$OPTARG" ;;
        m)  MAIL_ON_END=1; MAIL_ON_END_OPT=1 ;;
        s)  SKIP_WAIT=1 ;;
        h)  usage; exit 0 ;;
        :)  echo "error: -$OPTARG requires an argument" >&2; usage; exit 1 ;;
        \?) echo "error: unknown option -$OPTARG" >&2; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# BASE_PATH (the test-vector root) and OUTPUT_PATH (where the tests write their
# results) are required by every script in tc/scripts — run_common_setup.sh
# aborts without them. Check here too, before anything else happens: a run that
# cannot pass this has nothing to capture, and failing at the start costs a
# second instead of a probe, a reset device and a capture that ends in an empty
# log. Checked after getopts so '-h' still prints the usage.
MISSING_ENV=""
[ -n "${BASE_PATH:-}" ]   || MISSING_ENV="BASE_PATH"
[ -n "${OUTPUT_PATH:-}" ] || MISSING_ENV="${MISSING_ENV:+$MISSING_ENV and }OUTPUT_PATH"
if [ -n "$MISSING_ENV" ]; then
    echo "error: $MISSING_ENV not set — the tests in tc/scripts need both" >&2
    echo "       e.g. BASE_PATH=/mnt/archive/vdk_data/<release> OUTPUT_PATH=~/logs $(basename "$0")" >&2
    exit 1
fi

# Resolve the layout once: the split direction, the layout tmux re-evens with,
# and a detached session size with room for that arrangement (a detached session
# is 80x24 by default — too small to split more than a couple of times).
case "$TMUX_LAYOUT" in
    vertical)   TMUX_LAYOUT=vertical
                SPLIT_FLAG="-v"; TMUX_EVEN="even-vertical"
                SESSION_X=200; SESSION_Y=200 ;;
    horizontal) TMUX_LAYOUT=horizontal
                SPLIT_FLAG="-h"; TMUX_EVEN="even-horizontal"
                SESSION_X=300; SESSION_Y=50 ;;
    *)  echo "error: -l must be 'vertical' or 'horizontal' (got '$TMUX_LAYOUT')" >&2
        usage; exit 1 ;;
esac

DEFAULT_PORTS="/dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3"
PORTS_FROM_ENV="${PORTS+1}"     # non-empty only if the caller exported PORTS
PORTS="${PORTS:-$DEFAULT_PORTS}"
PREFIX="${PREFIX:-$HOME}"
BAUD="${BAUD:-115200}"
DURATION="${DURATION:-${1:-0}}"
case "$DURATION" in
    ''|*[!0-9]*) echo "error: duration must be a non-negative integer (got '$DURATION')" >&2; exit 1 ;;
esac
# $PWD, not $PREFIX: rbln_exec_tc.py writes app.log relative to its own working
# directory, which is the directory a test is started from — normally this one.
APP_LOG="${APP_LOG-$PWD/app.log}"
# host.log keeps everything the test script prints, and sits next to app.log so
# the two halves of one test — its own log and its console output — are found
# together. The directory comes from $APP_LOG even when rotation is off.
APP_LOG_DIR="$(dirname -- "${APP_LOG:-$PWD/app.log}")"
HOST_LOG="${HOST_LOG-$APP_LOG_DIR/host.log}"

# tc/scripts is found from this file's own location, never from $PWD: the tests
# live one level up from the directory holding this script, wherever the repo is
# checked out and whatever directory the run was started from.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TC_SCRIPTS_DIR="${TC_SCRIPTS_DIR:-$SCRIPT_DIR/../tc/scripts}"
[ -d "$TC_SCRIPTS_DIR" ] && TC_SCRIPTS_DIR="$(cd -- "$TC_SCRIPTS_DIR" && pwd)"

# Resolve the test to a full path up front: a name that does not exist should
# cost nothing, not a capture already running against a reset device. A '/'
# anywhere in it means the caller gave a path and means it.
case "$TEST_SCRIPT" in
    */*) TEST_SCRIPT_PATH="$TEST_SCRIPT" ;;
    *)   TEST_SCRIPT_PATH="$TC_SCRIPTS_DIR/$TEST_SCRIPT"
         # 'run_stress_test' is as good a name as 'run_stress_test.sh'.
         if [ ! -f "$TEST_SCRIPT_PATH" ] && [ -f "$TEST_SCRIPT_PATH.sh" ]; then
             TEST_SCRIPT_PATH="$TEST_SCRIPT_PATH.sh"
         fi ;;
esac
if [ ! -f "$TEST_SCRIPT_PATH" ]; then
    echo "error: test script not found: $TEST_SCRIPT_PATH" >&2
    echo "       tests available in $TC_SCRIPTS_DIR:" >&2
    # run_common_setup.sh is sourced by the others, not a test in itself.
    ls "$TC_SCRIPTS_DIR"/run_*.sh 2>/dev/null \
        | grep -v '/run_common_setup\.sh$' | sed 's|.*/|         |' >&2
    exit 1
fi
TEST_SCRIPT_PATH="$(cd -- "$(dirname -- "$TEST_SCRIPT_PATH")" && pwd)/$(basename "$TEST_SCRIPT_PATH")"

PROBE="${PROBE:-1}"
PROBE_CMD="${PROBE_CMD:-replay_ver}"
PROBE_WAIT="${PROBE_WAIT:-3}"
PROBE_ERR_RE="${PROBE_ERR_RE:-unknown|invalid|not found|not recognized|no such|syntax|error|usage}"
PROBE_OK_RE="${PROBE_OK_RE:-FINISHED}"
PROMPT="${PROMPT:-REBELLIONS$ }"
TYPE_DELAY="${TYPE_DELAY:-0.05}"
WAKE_GAP="${WAKE_GAP:-1.0}"

TMUX_VIEW="${TMUX_VIEW:-1}"
TMUX_VIEW_KILL="${TMUX_VIEW_KILL:-0}"

# Mail settings. The three credentials default to empty on purpose: an unset
# credential is the documented way to turn the notification off.
SMTP_HOST="${SMTP_HOST:-}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_TLS="${SMTP_TLS:-auto}"
SMTP_AUTH="${SMTP_AUTH:-auto}"
MAIL_TO="${MAIL_TO:-$SMTP_USER}"
MAIL_FROM="${MAIL_FROM:-$SMTP_USER}"
MAIL_ON_INT="${MAIL_ON_INT:-1}"
MAIL_TAIL_LINES="${MAIL_TAIL_LINES:-20}"
MAIL_DEBUG="${MAIL_DEBUG:-0}"
MAIL_ATTACH="${MAIL_ATTACH:-1}"
MAIL_ATTACH_GZIP="${MAIL_ATTACH_GZIP:-1}"
MAIL_ATTACH_MAX_KB="${MAIL_ATTACH_MAX_KB:-10240}"
MAIL_TIMEOUT="${MAIL_TIMEOUT:-120}"

# -m asks for a mail at the end of a run that finishes on its own, and there is
# nothing to send it with unless the SMTP credentials are set. Say which ones
# are missing now, not hours later when the capture ends and no mail arrives.
# SMTP_AUTH=none is the documented exception: a relay that accepts mail without
# logging in needs the host only, so SMTP_USER/SMTP_PASS are not asked for.
if [ "$MAIL_ON_END_OPT" = "1" ]; then
    MISSING_SMTP=""
    [ -n "$SMTP_HOST" ] || MISSING_SMTP="SMTP_HOST"
    if [ "$SMTP_AUTH" != "none" ]; then
        [ -n "$SMTP_USER" ] || MISSING_SMTP="${MISSING_SMTP:+$MISSING_SMTP, }SMTP_USER"
        [ -n "$SMTP_PASS" ] || MISSING_SMTP="${MISSING_SMTP:+$MISSING_SMTP, }SMTP_PASS"
    fi
    if [ -n "$MISSING_SMTP" ]; then
        echo "warn: -m given but $MISSING_SMTP not set — the email function is not triggered" >&2
        echo "      the capture and its logs are unaffected; set them to get the summary mail" >&2
    fi
fi

# An explicit PORTS is the caller's decision — never override it by probing.
[ -n "$PORTS_FROM_ENV" ] && PROBE=0
PORTS_SOURCE="$([ -n "$PORTS_FROM_ENV" ] && echo "given via \$PORTS" || echo "default (probe off)")"

# How long this run intends to capture, in words. -s wins over a duration: the
# test is the end of the run, so a duration given alongside it never applies and
# the banner says so rather than promising a wait that will not happen.
duration_desc() {
    if [ "$SKIP_WAIT" = "1" ]; then
        if [ "$DURATION" -gt 0 ]; then
            echo "ends with the test (-s; ${DURATION}s ignored)"
        else
            echo "ends with the test (-s)"
        fi
    elif [ "$DURATION" -gt 0 ]; then
        echo "${DURATION}s"
    else
        echo "until Ctrl-C"
    fi
}

# One shared timestamp per run so a port's logs sort together and never clobber.
TS="$(date +%Y%m%d_%H%M%S)"
START_EPOCH="$(date +%s)"
log_path() { echo "$PREFIX/serial_$(basename "$1")_$TS.log"; }

# Move a log out of the way instead of letting the next run append to it. The
# rotated name carries the file's own mtime, not this run's timestamp, so it says
# when the log was written rather than when it was set aside. app.log is written
# by a sudo'd python and can be root-owned; renaming it only needs write
# permission on the directory, and sudo covers the case where even that is
# missing. Never fatal — a log that cannot be rotated is reported and kept.
rotate_log() {
    local f="$1" stamp new n=1
    [ -n "$f" ] && [ -f "$f" ] || return 0
    stamp="$(date -r "$f" +%Y%m%d_%H%M%S 2>/dev/null)" || stamp=""
    [ -n "$stamp" ] || stamp="$TS"
    new="${f%.log}_$stamp.log"
    while [ -e "$new" ]; do new="${f%.log}_${stamp}_$n.log"; n=$((n + 1)); done
    if mv -- "$f" "$new" 2>/dev/null || sudo mv -- "$f" "$new" 2>/dev/null; then
        echo "rotated: $f -> $new"
    else
        echo "warn: could not rotate $f — the next test will append to it" >&2
    fi
}

# Same timestamp in the viewer session name, so a session is traceable to its
# logs and concurrent runs never collide.
TMUX_SESSION="${TMUX_SESSION:-serial_log_$TS}"

# Cleanup: stop the background readers and drop the probe scratch dir. Registered
# as a trap so an early exit (Ctrl-C, SIGTERM) tears everything down instead of
# leaving readers running. Idempotent via the CLEANED guard so the normal
# end-of-run path can also call it explicitly.
READERS=""
PROBE_TMPDIR=""
TMUX_VIEW_ACTIVE=0
CLEANED=0
INTERRUPTED=0
ACTIVE_PORTS=""     # set once detection is done; empty if Ctrl-C lands earlier

# --- end-of-run notification --------------------------------------------------
# Which endings mail: Ctrl-C by default, plus the capture finishing on its own
# when -m / MAIL_ON_END=1. Empty means no ending does.
mail_triggers() {
    local t=""
    [ "$MAIL_ON_INT" = "1" ] && t="Ctrl-C"
    [ "$MAIL_ON_END" = "1" ] && t="${t:+$t + }normal end"
    echo "$t"
}

# All three credentials must be present, plus curl to do the talking. Any gap
# means "the user didn't set this up" — say so once and skip, never fail the run.
# SMTP_AUTH=none is the one exception: an internal relay that takes mail without
# logging in still needs a host and addresses, but no username or password.
mail_skip_reason() {
    [ -n "$(mail_triggers)" ]       || { echo "MAIL_ON_INT=0, MAIL_ON_END=0"; return; }
    [ -n "$SMTP_HOST" ]             || { echo "SMTP_HOST not set"; return; }
    if [ "$SMTP_AUTH" != "none" ]; then
        [ -n "$SMTP_USER" ]         || { echo "SMTP_USER not set"; return; }
        [ -n "$SMTP_PASS" ]         || { echo "SMTP_PASS not set"; return; }
    fi
    [ -n "$MAIL_TO" ]               || { echo "MAIL_TO not set"; return; }
    [ -n "$MAIL_FROM" ]             || { echo "MAIL_FROM not set"; return; }
    command -v curl >/dev/null 2>&1 || { echo "curl not found"; return; }
    echo ""
}

# curl's SMTP failures are terse numbers; translate the ones that actually come
# up here into the setting the reader should go change.
mail_hint() {
    case "$1" in
        67) echo "server rejected the login — check SMTP_USER/SMTP_PASS (many providers need an app password, not the account password), or set SMTP_AUTH=none if this relay takes mail without authenticating" ;;
        6)  echo "could not resolve SMTP_HOST='$SMTP_HOST'" ;;
        7)  echo "could not connect to $SMTP_HOST:$SMTP_PORT — check host, port and firewall" ;;
        28) echo "timed out talking to $SMTP_HOST:$SMTP_PORT" ;;
        35|60|77|91) echo "TLS handshake failed — try SMTP_TLS=ssl with SMTP_PORT=465, or SMTP_TLS=starttls with SMTP_PORT=587" ;;
        55) echo "server refused the message — check that MAIL_FROM ('$MAIL_FROM') is an address this server lets you send as" ;;
        *)  echo "curl exit $1 — rerun with MAIL_DEBUG=1 to see the SMTP conversation" ;;
    esac
}

# Every log this run produced, one path per line, in the order the mail should
# present them: the serial captures first, then the test's own app.log and the
# host.log holding what it printed. Files that don't exist are left out, so a
# capture stopped before the test ran simply has fewer of them.
mail_log_files() {
    local p lg
    for p in $ACTIVE_PORTS; do
        lg="$(log_path "$p")"
        [ -f "$lg" ] && printf '%s\n' "$lg"
    done
    [ -n "$APP_LOG" ]  && [ -f "$APP_LOG" ]  && printf '%s\n' "$APP_LOG"
    [ -n "$HOST_LOG" ] && [ -f "$HOST_LOG" ] && printf '%s\n' "$HOST_LOG"
    return 0
}

# Serial logs already carry the run timestamp in their name; app.log and
# host.log don't, and two runs' worth of identically named attachments in one
# mail thread are impossible to tell apart — so stamp those two.
attach_name() {
    local b
    b="$(basename "$1")"
    case "$b" in
        app.log|host.log) b="${b%.log}_$TS.log" ;;
    esac
    printf '%s\n' "$b"
}

# Attachment plan: decide which log files ride along before the body is written,
# so the body can say what was attached and what was left out. Fills
# ATTACH_PLAN (a 'src<TAB>name<TAB>type' line per attachment) and ATTACH_NOTE
# (the human-readable version). These logs are plain text and compress roughly
# tenfold, so they are gzipped unless MAIL_ATTACH_GZIP=0; MAIL_ATTACH_MAX_KB
# caps the total so a long overnight capture can't produce a mail no server will
# accept. Whatever doesn't fit stays on disk and is named in the body.
ATTACH_PLAN=""
ATTACH_NOTE=""
plan_attachments() {
    local tmpd="$1" lg name src type kb total=0 note="" skipped=0
    ATTACH_PLAN="$tmpd/attach.plan"; : > "$ATTACH_PLAN"
    ATTACH_NOTE=""
    [ "$MAIL_ATTACH" = "1" ] || { ATTACH_NOTE="attachments: off (MAIL_ATTACH=0)"; return 0; }
    command -v base64 >/dev/null 2>&1 || {
        ATTACH_NOTE="attachments: skipped (base64 not found)"; return 0; }

    while IFS= read -r lg; do
        [ -f "$lg" ] || continue
        name="$(attach_name "$lg")"
        src="$lg"
        type="text/plain; charset=UTF-8"
        if [ "$MAIL_ATTACH_GZIP" = "1" ] && command -v gzip >/dev/null 2>&1 \
           && gzip -c "$lg" > "$tmpd/$name.gz" 2>/dev/null; then
            src="$tmpd/$name.gz"; name="$name.gz"; type="application/gzip"
        fi
        kb=$(( ( $(wc -c < "$src") + 1023 ) / 1024 ))
        if [ "$MAIL_ATTACH_MAX_KB" -gt 0 ] && [ $((total + kb)) -gt "$MAIL_ATTACH_MAX_KB" ]; then
            note="$note
  $name — NOT attached, ${kb}KB would exceed MAIL_ATTACH_MAX_KB=$MAIL_ATTACH_MAX_KB (full file is on $(hostname) at $lg)"
            skipped=1
            continue
        fi
        total=$((total + kb))
        printf '%s\t%s\t%s\n' "$src" "$name" "$type" >> "$ATTACH_PLAN"
        note="$note
  $name (${kb}KB)"
    done < <(mail_log_files)

    if [ -s "$ATTACH_PLAN" ]; then
        ATTACH_NOTE="attached ($([ "$MAIL_ATTACH_GZIP" = "1" ] && echo "gzipped, ")${total}KB total):$note"
    elif [ "$skipped" = "1" ]; then
        ATTACH_NOTE="attachments: none fit under MAIL_ATTACH_MAX_KB=$MAIL_ATTACH_MAX_KB:$note"
    fi
}

# Emit the base64 MIME parts for the planned attachments. Lines get CRLF like
# the rest of the message; base64 wraps at 76 columns on its own.
emit_attachments() {
    local boundary="$1" src name type
    [ -s "$ATTACH_PLAN" ] || return 0
    while IFS="$(printf '\t')" read -r src name type; do
        printf -- '--%s\r\n' "$boundary"
        printf 'Content-Type: %s; name="%s"\r\n' "$type" "$name"
        printf 'Content-Transfer-Encoding: base64\r\n'
        printf 'Content-Disposition: attachment; filename="%s"\r\n' "$name"
        printf '\r\n'
        base64 "$src" | sed -e 's/$/\r/'
    done < "$ATTACH_PLAN"
}

# The report the mail carries: what ran, for how long, and the tail of each log
# so the reader gets the last thing every port and the test itself said without
# opening a file.
mail_body() {
    local now elapsed lg
    now="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    elapsed=$(( $(date +%s) - START_EPOCH ))
    echo "Serial capture ${MAIL_REASON}."
    echo
    printf '  %-10s %s\n' "host:"    "$(hostname)"
    printf '  %-10s %s\n' "user:"    "${USER:-$(id -un)}"
    printf '  %-10s %s\n' "script:"  "$(basename "$0")"
    printf '  %-10s %s\n' "started:" "$(date -d "@$START_EPOCH" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$TS")"
    printf '  %-10s %s\n' "stopped:" "$now"
    printf '  %-10s %s\n' "elapsed:" "${elapsed}s"
    printf '  %-10s %s\n' "ports:"   "${ACTIVE_PORTS:-none (interrupted before capture started)}"
    printf '  %-10s %s\n' "source:"  "$PORTS_SOURCE"
    printf '  %-10s %s\n' "baud:"    "$BAUD"
    printf '  %-10s %s\n' "test:"    "$TEST_SCRIPT_PATH"

    echo
    echo "logs:"
    while IFS= read -r lg; do
        printf '  %s (%s)\n' "$lg" "$(du -h "$lg" 2>/dev/null | cut -f1 || echo '?')"
    done < <(mail_log_files)
    if [ -n "$ATTACH_NOTE" ]; then
        echo
        echo "$ATTACH_NOTE"
    fi
    [ "$MAIL_TAIL_LINES" -gt 0 ] 2>/dev/null || return 0
    while IFS= read -r lg; do
        echo
        echo "----- $lg (last $MAIL_TAIL_LINES lines) -----"
        tail -n "$MAIL_TAIL_LINES" "$lg" 2>/dev/null | tr -d '\000\r'
    done < <(mail_log_files)
}

# Hand the message to curl's SMTP client. Credentials go through a 0600 config
# file, never the command line, so they can't be read out of `ps`.
send_mail() {
    local subject="$1" tmpd msg conf url rcpt rc rcpts header_to boundary
    tmpd="$(mktemp -d)" || return 1
    msg="$tmpd/message"
    conf="$tmpd/curlrc"

    # MAIL_TO is accepted comma- and/or space-separated; normalise to one
    # address per word so the header and the envelope agree.
    rcpts="$(echo "$MAIL_TO" | tr ',' ' ')"
    header_to=""
    for rcpt in $rcpts; do
        header_to="${header_to:+$header_to, }$rcpt"
    done

    plan_attachments "$tmpd"
    # Run timestamp plus PID: unique per run, and '=_' can't occur in base64 or
    # in the plain-text body, so the boundary can never collide with content.
    boundary="=_serial_log_${TS}_$$"

    {
        printf 'From: %s\r\n' "$MAIL_FROM"
        printf 'To: %s\r\n' "$header_to"
        printf 'Subject: %s\r\n' "$subject"
        printf 'Date: %s\r\n' "$(date -R)"
        printf 'MIME-Version: 1.0\r\n'
        if [ -s "$ATTACH_PLAN" ]; then
            # multipart/mixed: the summary first, then one part per log file.
            printf 'Content-Type: multipart/mixed; boundary="%s"\r\n' "$boundary"
            printf '\r\n'
            printf -- '--%s\r\n' "$boundary"
            printf 'Content-Type: text/plain; charset=UTF-8\r\n'
            printf '\r\n'
            mail_body | sed -e 's/$/\r/'
            emit_attachments "$boundary"
            printf -- '--%s--\r\n' "$boundary"
        else
            printf 'Content-Type: text/plain; charset=UTF-8\r\n'
            printf '\r\n'
            mail_body | sed -e 's/$/\r/'
        fi
    } > "$msg"

    # Port 465 is implicit TLS (smtps://); everything else upgrades with
    # STARTTLS, which --ssl-reqd makes mandatory rather than best-effort.
    case "$SMTP_TLS" in
        ssl)      url="smtps://$SMTP_HOST:$SMTP_PORT"; set -- --ssl-reqd ;;
        starttls) url="smtp://$SMTP_HOST:$SMTP_PORT";  set -- --ssl-reqd ;;
        none)     url="smtp://$SMTP_HOST:$SMTP_PORT";  set -- ;;
        auto|*)   if [ "$SMTP_PORT" = "465" ]; then
                      url="smtps://$SMTP_HOST:$SMTP_PORT"
                  else
                      url="smtp://$SMTP_HOST:$SMTP_PORT"
                  fi
                  set -- --ssl-reqd ;;
    esac

    # Credentials go through a 0600 config file, never the command line, so they
    # can't be read out of `ps`. SMTP_AUTH pins the mechanism when a server
    # advertises one it can't actually complete; 'none' skips AUTH entirely.
    case "$SMTP_AUTH" in
        none) : ;;
        auto) ( umask 077; printf 'user = "%s:%s"\n' "$SMTP_USER" "$SMTP_PASS" > "$conf" )
              set -- "$@" -K "$conf" ;;
        *)    ( umask 077; printf 'user = "%s:%s"\n' "$SMTP_USER" "$SMTP_PASS" > "$conf" )
              set -- "$@" -K "$conf" \
                    --login-options "AUTH=$(echo "$SMTP_AUTH" | tr '[:lower:]' '[:upper:]')" ;;
    esac

    for rcpt in $rcpts; do
        set -- "$@" --mail-rcpt "$rcpt"
    done
    [ "$MAIL_DEBUG" = "1" ] && set -- "$@" --verbose

    curl --silent --show-error --connect-timeout 15 --max-time "$MAIL_TIMEOUT" \
         --url "$url" --mail-from "$MAIL_FROM" "$@" \
         --upload-file "$msg" >&2
    rc=$?
    rm -rf "$tmpd"
    return $rc
}

# Mail one ending. $1 is how the run ended, as a subject word ('interrupted',
# 'finished'); $2 is the sentence the body opens with. MAIL_SENT keeps a Ctrl-C
# during the normal-end send from mailing the same run twice.
MAIL_SENT=0
MAIL_REASON=""
notify_mail() {
    local what="$1" why rc addr
    MAIL_REASON="$2"
    [ "$MAIL_SENT" = "1" ] && return 0
    why="$(mail_skip_reason)"
    if [ -n "$why" ]; then
        echo "mail: skipped ($why)" >&2
        return 0
    fi
    MAIL_SENT=1
    # A bare username here reaches no mailbox; the send may even succeed and the
    # mail then vanish, so say it before that happens rather than after.
    for addr in $MAIL_FROM $(echo "$MAIL_TO" | tr ',' ' '); do
        case "$addr" in
            *@*) ;;
            *) echo "warn: '$addr' is not a full email address — set MAIL_TO/MAIL_FROM explicitly" >&2 ;;
        esac
    done
    echo "mail: sending run summary to $MAIL_TO ..." >&2
    if send_mail "[serial_log] capture $what on $(hostname) at $TS"; then
        echo "mail: sent" >&2
    else
        rc=$?
        echo "warn: mail not sent: $(mail_hint "$rc")" >&2
        echo "warn: capture and logs are unaffected" >&2
    fi
}
# -----------------------------------------------------------------------------

cleanup() {
    [ "$CLEANED" = "1" ] && return
    CLEANED=1
    for pid in $READERS; do kill "$pid" 2>/dev/null; done
    for pid in $READERS; do wait "$pid" 2>/dev/null; done
    [ -n "$PROBE_TMPDIR" ] && rm -rf "$PROBE_TMPDIR"
    # The viewer outlives the run by default so the logs stay on screen; only
    # tear it down when the caller asked for that.
    if [ "$TMUX_VIEW_ACTIVE" = "1" ] && [ "$TMUX_VIEW_KILL" = "1" ]; then
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null
    fi
}
# On the way out: always tear down first, so the readers are stopped and the
# logs are complete before the mail quotes them. Only a Ctrl-C exit mails from
# here — the normal ending mails from the end of the script, once the summary
# has been printed.
on_exit() {
    cleanup
    if [ "$INTERRUPTED" = "1" ] && [ "$MAIL_ON_INT" = "1" ]; then
        notify_mail "interrupted" "stopped by Ctrl-C (SIGINT)"
    fi
    return 0
}
trap on_exit EXIT
trap 'INTERRUPTED=1; exit 130' INT
trap 'exit 143' TERM

# Probe one port: wake the console, type $PROBE_CMD, and read whatever comes
# back for $PROBE_WAIT seconds. The port counts as usable only if the reply
# holds something beyond the device's own echo and the prompt, and doesn't look
# like a "no such command" complaint. Returns 0 = usable, 1 = not.
# Sent one character at a time (like serial_run.sh) so devices with slow UART
# handlers don't drop input.
probe_port() {
    local p="$1" tmp rpid resp i
    stty -F "$p" "$BAUD" cs8 -cstopb -parenb \
        raw -echo -echoe -echok -echoctl -echoke \
        -icrnl -inlcr -igncr -ixon -ixoff 2>/dev/null || return 1

    tmp="$PROBE_TMPDIR/$(basename "$p").probe"
    # Check the port opens read/write in a subshell first: a failed redirection
    # on `exec` would kill this (non-interactive) shell outright.
    ( : <>"$p" ) 2>/dev/null || return 1
    exec 8<>"$p"
    ( exec timeout "$PROBE_WAIT" stdbuf -o0 cat <&8 > "$tmp" ) &
    rpid=$!
    sleep 0.3
    printf '\r' >&8
    sleep "$WAKE_GAP"
    i=0
    while [ $i -lt ${#PROBE_CMD} ]; do
        printf '%s' "${PROBE_CMD:$i:1}" >&8
        sleep "$TYPE_DELAY"
        i=$((i + 1))
    done
    printf '\r' >&8
    wait "$rpid" 2>/dev/null
    exec 8<&- 8>&-

    # NULs and CRs are framing noise from these consoles, not content.
    resp="$(tr -d '\000\r' < "$tmp")"
    resp="${resp//$PROBE_CMD/}"     # drop the device's echo of what we typed
    resp="${resp//$PROMPT/}"        # drop bare prompts — those aren't an answer
    # Also drop any prompt-like leading token (REBELLIONS$, RBLN#, =>, ...), so a
    # console that merely echoed the command back at its own prompt and printed
    # nothing — i.e. does not implement the command — is not mistaken for a reply.
    resp="$(printf '%s\n' "$resp" | sed -E 's/^[^[:space:]]{0,32}[$#>%][[:space:]]*//')"
    printf '%s\n' "$resp" | grep -qiE -- "$PROBE_ERR_RE" && return 1
    printf '%s\n' "$resp" | grep -q '[^[:space:]]' || return 1
    # Positive check: the reply must carry the console's completion marker
    # ('-> FINISHED'), so a port that is merely busy printing its own boot log
    # can't pass on that unrelated traffic. Clear PROBE_OK_RE to skip this.
    if [ -n "$PROBE_OK_RE" ]; then
        printf '%s\n' "$resp" | grep -qiE -- "$PROBE_OK_RE" || return 1
    fi
    return 0
}

# Detection pass: probe every /dev/ttyUSB* serially (one port at a time, so no
# two probes fight over the same USB bridge) and keep the ones that answer.
if [ "$PROBE" = "1" ]; then
    if ! command -v timeout >/dev/null 2>&1 || ! command -v stdbuf >/dev/null 2>&1; then
        echo "warn: port probe needs 'timeout' and 'stdbuf' — skipping probe (set PORTS or PROBE=0)" >&2
        PORTS="$DEFAULT_PORTS"
        PORTS_SOURCE="default (probe skipped: missing timeout/stdbuf)"
    else
        PROBE_TMPDIR="$(mktemp -d)"
        DETECTED=""
        echo "detecting ports that answer '$PROBE_CMD'..."
        for p in /dev/ttyUSB*; do
            [ -e "$p" ] || continue     # unmatched glob stays literal
            if probe_port "$p"; then
                echo "  $p — ok"
                DETECTED="$DETECTED $p"
            else
                echo "  $p — no answer"
            fi
        done
        if [ -n "$DETECTED" ]; then
            PORTS="${DETECTED# }"
            PORTS_SOURCE="probed with '$PROBE_CMD'"
        else
            echo "warn: no port answered '$PROBE_CMD' — falling back to defaults" >&2
            PORTS="$DEFAULT_PORTS"
            PORTS_SOURCE="default (nothing answered '$PROBE_CMD')"
        fi
    fi
fi

# At least one port must exist; absent ports are skipped with a warning (the
# fallback list is fixed, so not every ttyUSB* is necessarily present).
ACTIVE_PORTS=""
for p in $PORTS; do
    if [ -e "$p" ]; then
        ACTIVE_PORTS="$ACTIVE_PORTS $p"
    else
        echo "warn: $p not found — skipping" >&2
    fi
done
[ -n "$ACTIVE_PORTS" ] || { echo "error: no ports found to capture" >&2; exit 2; }
ACTIVE_PORTS="${ACTIVE_PORTS# }"

# Configure every captured line: 8N1, raw, no echo / no flow control munging.
for p in $ACTIVE_PORTS; do
    stty -F "$p" "$BAUD" cs8 -cstopb -parenb \
        raw -echo -echoe -echok -echoctl -echoke \
        -icrnl -inlcr -igncr -ixon -ixoff \
        || { echo "error: stty failed on $p" >&2; exit 3; }
done

echo "============================ serial logging =============================="
printf '  %-13s %s\n' "PORTS"    "$ACTIVE_PORTS"
printf '  %-13s %s\n' "SOURCE"   "$PORTS_SOURCE"
printf '  %-13s %s\n' "PREFIX"   "$PREFIX"
printf '  %-13s %s\n' "BAUD"     "$BAUD"
printf '  %-13s %s\n' "DURATION" "$(duration_desc)"
printf '  %-13s %s\n' "TEST"     "$TEST_SCRIPT_PATH"
printf '  %-13s %s\n' "APP_LOG"  "${APP_LOG:-not rotated (APP_LOG empty)}"
printf '  %-13s %s\n' "HOST_LOG" "${HOST_LOG:-not written (HOST_LOG empty)}"
printf '  %-13s %s\n' "LAYOUT"   "$([ "$TMUX_VIEW" = "1" ] && echo "$TMUX_LAYOUT" || echo "no viewer")"
MAIL_SKIP="$(mail_skip_reason)"
printf '  %-13s %s\n' "MAIL"     "$([ -z "$MAIL_SKIP" ] && echo "on $(mail_triggers) -> $MAIL_TO" || echo "off ($MAIL_SKIP)")"
echo "---------------------------------------------------------------------------"
for p in $ACTIVE_PORTS; do
    printf '  %-13s %s\n' "log" "$(log_path "$p")"
done
echo "==========================================================================="

# The capture starts here, so this is the moment to set the previous test's
# app.log aside: whatever a test writes from now on belongs to this capture.
rotate_log "$APP_LOG"

# Background readers: one per port, each copying serial -> its own log file,
# unbuffered so logs update in real time. Each reader is exec'd so $! is the
# reader process itself — a single kill reaps it with no orphaned children left.
STDBUF=()
if command -v stdbuf >/dev/null 2>&1; then
    STDBUF=(stdbuf -o0)
else
    echo "warn: stdbuf not found — serial logs may update in larger chunks" >&2
fi
for p in $ACTIVE_PORTS; do
    lg="$(log_path "$p")"
    : > "$lg"
    ( exec "${STDBUF[@]}" cat "$p" > "$lg" ) &
    READERS="$READERS $!"
done

# Live viewer: a detached tmux session with one 'tail -F' pane per log file, all
# in a single column or row depending on -l. Detached so this script keeps
# running headless — attach when you want to watch. Purely a convenience: any
# failure here warns and leaves the capture untouched.
tmux_view() {
    local first=1 idx=0 lg cmd
    command -v tmux >/dev/null 2>&1 || { echo "warn: tmux not found — no viewer" >&2; return 1; }
    for p in $ACTIVE_PORTS; do
        lg="$(log_path "$p")"
        # -n +1 starts at the top of the file, -F keeps following it.
        cmd="tail -n +1 -F $(printf %q "$lg")"
        if [ "$first" = "1" ]; then
            tmux new-session -d -s "$TMUX_SESSION" -n logs \
                    -x "$SESSION_X" -y "$SESSION_Y" "$cmd" \
                || { echo "warn: tmux new-session failed — no viewer" >&2; return 1; }
            first=0
        else
            tmux split-window "$SPLIT_FLAG" -t "$TMUX_SESSION:logs" "$cmd" \
                || { echo "warn: tmux split-window failed for $lg" >&2; continue; }
            # Re-even after each split so later splits still have room.
            tmux select-layout -t "$TMUX_SESSION:logs" "$TMUX_EVEN" >/dev/null
        fi
        tmux select-pane -t "$TMUX_SESSION:logs.$idx" -T "$(basename "$lg")" 2>/dev/null
        idx=$((idx + 1))
    done
    # Label each pane with its file; harmless if the tmux build ignores it.
    tmux set-option -t "$TMUX_SESSION" pane-border-status top 2>/dev/null
    tmux select-layout -t "$TMUX_SESSION:logs" "$TMUX_EVEN" >/dev/null
    # Keep panes up after the tails die so the last output stays readable.
    tmux set-option -t "$TMUX_SESSION" remain-on-exit on 2>/dev/null
    return 0
}

if [ "$TMUX_VIEW" = "1" ] && tmux_view; then
    TMUX_VIEW_ACTIVE=1
    echo "viewer:  tmux attach -t $TMUX_SESSION   ($(echo $ACTIVE_PORTS | wc -w) panes, $TMUX_LAYOUT)"
fi

echo "INFO: Wait for 10 seconds"
sleep 10
echo "INFO: run test script $TEST_SCRIPT_PATH"

# Run it the way the file asks to be run: directly when it is executable, so its
# own shebang decides, and through bash when the execute bit is missing.
run_test_script() {
    if [ -x "$TEST_SCRIPT_PATH" ]; then
        "$TEST_SCRIPT_PATH"
    else
        bash "$TEST_SCRIPT_PATH"
    fi
}

# Everything the test prints, stdout and stderr alike, goes to host.log as well
# as to the screen — so a run that scrolled past, or one nobody was watching,
# can still be read afterwards. The previous host.log is rotated out of the way
# first, like app.log, so each file holds one test.
TEST_RC=0
if [ -n "$HOST_LOG" ]; then
    rotate_log "$HOST_LOG"
    run_test_script 2>&1 | tee -- "$HOST_LOG"
    TEST_RC=${PIPESTATUS[0]}
else
    run_test_script
    TEST_RC=$?
fi

# Capture until Ctrl-C, or DURATION seconds if a positive duration was given —
# unless -s, which makes the test the end of the run: nothing is waited for once
# it returns, so an unattended run finishes on its own.
if [ "$SKIP_WAIT" = "1" ]; then
    echo "test done — ending the capture without waiting (-s)"
elif [ "$DURATION" -gt 0 ]; then
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
if [ "$TMUX_VIEW_ACTIVE" = "1" ] && [ "$TMUX_VIEW_KILL" != "1" ]; then
    echo "viewer still up:"
    printf '  tmux attach -t %s\n' "$TMUX_SESSION"
    printf '  tmux kill-session -t %s\n' "$TMUX_SESSION"
fi

# The run reached its own end (-m mails this; Ctrl-C never gets here, it mails
# from the EXIT trap). Sent after the summary so the console isn't held up by
# the delivery.
if [ "$MAIL_ON_END" = "1" ]; then
    if [ "$SKIP_WAIT" = "1" ]; then
        notify_mail "finished" "ended when the test finished (-s)"
    elif [ "$DURATION" -gt 0 ]; then
        notify_mail "finished" "finished after the full ${DURATION}s"
    else
        notify_mail "finished" "ended — every port's reader stopped"
    fi
fi

exit "${TEST_RC:-0}"
