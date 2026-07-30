#!/usr/bin/env python3
"""
serial_run.py — send one command to a target serial console while capturing
every defined port in parallel, each to its own timestamped log file, and exit
when the target device's prompt reappears (= command actually finished).

The command is sent to exactly ONE port (PORT). Every port in PORTS is opened
for reading at the same time — a command on one console can produce side-effect
output on the others — and each port's incoming text is written to its own log.

Usage:
    serial_run.py "<command>"

Env overrides:
    PORTS       ports to capture, space-separated  (default: /dev/ttyUSB0..3)
    PORT        target port the command is sent to (default: first of PORTS)
    PREFIX      directory for per-port log files    (default: $HOME)
    BAUD        baud rate                           (default: 115200)
    PROMPT      shell prompt to wait for            (default: REBELLIONS$)
    IDLE_TIMEOUT  abort if no new bytes for N sec   (default: 30)
    MAX_TIMEOUT   absolute max total wait, 0=off    (default: 0)
    TAIL_S      grace period after prompt is seen   (default: 0.5)
    WAKE        send a wake CR before command       (default: 1)
    EOL         line ending: cr | lf | crlf         (default: cr)
    TYPE_DELAY  seconds between characters          (default: 0.05)
    DTR         assert DTR (1) or drop (0)          (default: 1)
    RTS         assert RTS (1) or drop (0)          (default: 1)

Each run writes one log per captured port:
    $PREFIX/serial_<port>_<YYYYmmdd_HHMMSS>.log
The timestamp is shared across a run and never overwritten, so history is kept.
"""

import os
import sys
import time
import threading
import termios
from datetime import datetime

import serial


def disable_hupcl_and_flow(fd):
    """Clear HUPCL (so DTR stays asserted on close) and software flow control."""
    attrs = termios.tcgetattr(fd)
    iflag, oflag, cflag, lflag, ispeed, ospeed, cc = attrs
    cflag &= ~termios.HUPCL
    cflag |= termios.CLOCAL
    iflag &= ~(termios.IXON | termios.IXOFF | termios.IXANY)
    termios.tcsetattr(fd, termios.TCSANOW, [iflag, oflag, cflag, lflag, ispeed, ospeed, cc])


def env(name, default, cast=str):
    v = os.environ.get(name)
    return cast(v) if v is not None else default


def open_port(port, baud, dtr, rts):
    ser = serial.Serial(
        port=port,
        baudrate=baud,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=0.1,
        xonxoff=False,
        rtscts=False,
        dsrdtr=False,
    )
    ser.dtr = bool(dtr)
    ser.rts = bool(rts)
    # Keep DTR asserted across close, kill any software flow control.
    try:
        disable_hupcl_and_flow(ser.fileno())
    except Exception as e:
        print(f"warn: could not adjust termios on {port}: {e}", file=sys.stderr)
    return ser


def main():
    if len(sys.argv) < 2:
        print('usage: serial_run.py "<command>"', file=sys.stderr)
        return 1

    cmd = " ".join(sys.argv[1:])
    ports = env("PORTS", "/dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3").split()
    port = env("PORT", ports[0] if ports else "/dev/ttyUSB0")
    prefix = env("PREFIX", os.path.expanduser("~"))
    baud = env("BAUD", 115200, int)
    prompt_str = env("PROMPT", "REBELLIONS$")
    idle_timeout = env("IDLE_TIMEOUT", 30.0, float)
    max_timeout = env("MAX_TIMEOUT", 0.0, float)
    tail_s = env("TAIL_S", 0.5, float)
    wake = env("WAKE", 1, int)
    eol_name = env("EOL", "cr").lower()
    type_delay = env("TYPE_DELAY", 0.05, float)
    dtr = env("DTR", 1, int)
    rts = env("RTS", 1, int)

    eol_map = {"cr": b"\r", "lf": b"\n", "crlf": b"\r\n"}
    if eol_name not in eol_map:
        print("error: EOL must be cr|lf|crlf", file=sys.stderr)
        return 1
    eol = eol_map[eol_name]

    # Make sure the target port is part of the captured set.
    if port not in ports:
        ports.insert(0, port)

    # The target must exist; other ports are skipped with a warning if absent
    # (the default list is fixed, so not every ttyUSB* is necessarily present).
    if not os.path.exists(port):
        print(f"error: target {port} not found", file=sys.stderr)
        return 2
    active_ports = []
    for p in ports:
        if os.path.exists(p):
            active_ports.append(p)
        else:
            print(f"warn: {p} not found — skipping", file=sys.stderr)

    # One shared timestamp per run so a port's logs sort together and never clobber.
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    def log_path(p):
        return os.path.join(prefix, f"serial_{os.path.basename(p)}_{ts}.log")

    os.makedirs(prefix, exist_ok=True)

    print("============================ serial connection ============================")
    print(f"  {'PORTS':<13}{' '.join(active_ports)}")
    print(f"  {'PORT':<13}{port} (target)")
    print(f"  {'PREFIX':<13}{prefix}")
    print(f"  {'BAUD':<13}{baud}")
    print(f"  {'PROMPT':<13}{prompt_str}")
    print(f"  {'EOL':<13}{eol_name}")
    print(f"  {'IDLE_TIMEOUT':<13}{idle_timeout}s")
    print(f"  {'MAX_TIMEOUT':<13}{max_timeout}s" if max_timeout > 0 else f"  {'MAX_TIMEOUT':<13}off")
    print(f"  {'TAIL_S':<13}{tail_s}s")
    print(f"  {'WAKE':<13}{'yes' if wake else 'no'}")
    print("---------------------------------------------------------------------------")
    for p in active_ports:
        print(f"  {'log':<13}{log_path(p)}")
    print("---------------------------------------------------------------------------")
    print(f"  {'command':<13}{cmd!r}")
    print("===========================================================================")

    stop = threading.Event()
    target_buffer = bytearray()      # only the target feeds prompt detection
    target_lock = threading.Lock()
    last_rx = [time.monotonic()]     # updated by the target reader only

    sers = []
    logs = []
    threads = []

    def make_reader(ser, logfh, is_target):
        def reader():
            while not stop.is_set():
                try:
                    data = ser.read(4096)
                except serial.SerialException:
                    break
                if not data:
                    continue
                logfh.write(data)
                logfh.flush()
                if is_target:
                    with target_lock:
                        target_buffer.extend(data)
                    last_rx[0] = time.monotonic()
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
        return reader

    # Open every active port and start a reader that copies it to its own log.
    # The target port also mirrors to stdout and feeds prompt detection.
    target_ser = None
    for p in active_ports:
        ser = open_port(p, baud, dtr, rts)
        logfh = open(log_path(p), "wb")
        sers.append(ser)
        logs.append(logfh)
        is_target = (p == port)
        if is_target:
            target_ser = ser
        t = threading.Thread(target=make_reader(ser, logfh, is_target), daemon=True)
        t.start()
        threads.append(t)

    time.sleep(0.3)
    if wake:
        target_ser.write(eol)
        target_ser.flush()
        time.sleep(1.0)

    # Snapshot how much we've received on the target before sending — we'll only
    # look for the prompt in bytes that arrive AFTER this point.
    with target_lock:
        cmd_offset = len(target_buffer)

    for ch in cmd.encode():
        target_ser.write(bytes([ch]))
        target_ser.flush()
        if type_delay > 0:
            time.sleep(type_delay)
    target_ser.write(eol)
    target_ser.flush()

    # Wait for the prompt to reappear on the target — that means the command
    # finished. Reset the idle timer now (so the wake-prompt latency doesn't
    # count) and keep waiting as long as the target is still emitting bytes.
    prompt_bytes = prompt_str.encode()
    last_rx[0] = time.monotonic()
    cmd_start = time.monotonic()
    finished = False
    abort_reason = ""
    while True:
        with target_lock:
            new_data = bytes(target_buffer[cmd_offset:])
        if prompt_bytes in new_data:
            time.sleep(tail_s)  # let any trailing output flush
            finished = True
            break
        now = time.monotonic()
        if now - last_rx[0] > idle_timeout:
            abort_reason = f"no new bytes for {idle_timeout}s"
            break
        if max_timeout > 0 and now - cmd_start > max_timeout:
            abort_reason = f"max wall-clock {max_timeout}s reached"
            break
        time.sleep(0.1)

    stop.set()
    for t in threads:
        t.join(timeout=2)
    for ser in sers:
        ser.close()
    for logfh in logs:
        logfh.close()

    print()
    if finished:
        print("===== end =====")
    else:
        print(f"===== timeout: {abort_reason} — prompt {prompt_str!r} not seen =====",
              file=sys.stderr)
    print("logs:")
    for p in active_ports:
        print(f"  {log_path(p)}")
    return 0 if finished else 4


if __name__ == "__main__":
    sys.exit(main())
