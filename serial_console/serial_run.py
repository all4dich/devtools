#!/usr/bin/env python3
"""
serial_run.py — open a serial console, send one command, print everything to
stdout, exit when the device's prompt reappears (= command actually finished).

Usage:
    serial_run.py "<command>"

Env overrides:
    PORT        serial device                       (default: /dev/ttyUSB0)
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
"""

import os
import sys
import time
import threading
import termios

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


def main():
    if len(sys.argv) < 2:
        print('usage: serial_run.py "<command>"', file=sys.stderr)
        return 1

    cmd = " ".join(sys.argv[1:])
    port = env("PORT", "/dev/ttyUSB0")
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

    if not os.path.exists(port):
        print(f"error: {port} not found", file=sys.stderr)
        return 2

    print(f">>> {port} @ {baud} — sending: {cmd!r}")

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
        print(f"warn: could not adjust termios: {e}", file=sys.stderr)

    stop = threading.Event()
    buffer = bytearray()
    buffer_lock = threading.Lock()
    last_rx = [time.monotonic()]   # mutable holder so the reader can update it

    def reader():
        while not stop.is_set():
            try:
                data = ser.read(4096)
            except serial.SerialException:
                break
            if data:
                with buffer_lock:
                    buffer.extend(data)
                last_rx[0] = time.monotonic()
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()

    t = threading.Thread(target=reader, daemon=True)
    t.start()

    time.sleep(0.3)
    if wake:
        ser.write(eol)
        ser.flush()
        time.sleep(1.0)

    # Snapshot how much we have received before sending — we'll only look for
    # the prompt in bytes that arrive AFTER this point.
    with buffer_lock:
        cmd_offset = len(buffer)

    for ch in cmd.encode():
        ser.write(bytes([ch]))
        ser.flush()
        if type_delay > 0:
            time.sleep(type_delay)
    ser.write(eol)
    ser.flush()

    # Wait for the prompt to reappear — that means the command finished.
    # Reset idle timer now (so the wake-prompt latency doesn't count) and
    # keep waiting as long as the device is still emitting bytes.
    prompt_bytes = prompt_str.encode()
    last_rx[0] = time.monotonic()
    cmd_start = time.monotonic()
    finished = False
    abort_reason = ""
    while True:
        with buffer_lock:
            new_data = bytes(buffer[cmd_offset:])
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
    t.join(timeout=2)
    ser.close()

    print()
    if finished:
        print("===== end =====")
    else:
        print(f"===== timeout: {abort_reason} — prompt {prompt_str!r} not seen =====",
              file=sys.stderr)
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
