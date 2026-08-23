#!/usr/bin/env python3
"""A fake mpv JSON-IPC peer, for the awkward shapes the real one produces.

Every IPC rule in the suite exists because of a shape this mock can produce on demand, and
none of them can be exercised against a real mpv reliably — you cannot ask mpv to answer out
of order, or to stall, on cue.

  --reverse    answer the three get_property requests in REVERSE order. This is what forces
               correlation by request_id: a reader that trusts line order silently puts the
               duration in the position slot.
  --null KEY   report KEY as JSON null — a freshly launched player has no time-pos yet, and
               "null" must render as --:-- rather than as a crash or a zero.
  --noisy      interleave async events (no request_id) around every reply. mpv multiplexes
               property-change events into every client's stream, so a reader that takes the
               first line it sees reads an event as its answer.
  --advance    make time-pos / percent-pos WALK with the wall clock, the way a playing mpv
               does. Without it every redraw is byte-identical and a "did the view tick?"
               test cannot tell a frozen pane from a correct repaint.
  --vol N      starting volume; set_property volume is applied and appended to --log, which
               is how "9/0 moved the real value, not just the display" is checked.
  --paused     start with pause=true, i.e. a player somebody else parked. --status and the
               TUI banner must both report that without having been told.
  --log PATH   where set_property writes land.

The peer NEVER closes its side. That is the point of the default configuration: `nc -U -w1`
against a peer that keeps the socket open pays the full timeout unless the reader breaks on
its own reply — the behaviour the whole read path is written around.

Usage:  ./mpv_ipc_mock.py <socket-path> [options]
Then point the client at it:  CURRENT_PLAY_SOCK=<socket-path>

This one mock replaces three earlier probes (a minimal never-closes peer and an
event-injecting one); their behaviour is this file's default and its --noisy flag.
"""
import os, socket, threading, sys, json, time
args = sys.argv[1:]
sock_path = args[0]
def opt(name, default=None):
    return args[args.index(name) + 1] if name in args else default
REVERSE = "--reverse" in args
# --advance makes time-pos/percent-pos WALK with the wall clock, the way a playing mpv does.
# Without it every redraw is byte-identical and a "did the view tick?" test cannot tell a
# frozen pane from a correct repaint.
ADVANCE = "--advance" in args
T0 = time.time()
NOISY = "--noisy" in args
NULLS = {opt("--null", "")}
LOG = opt("--log", "/dev/null")
# pause is a BOOLEAN, and it is the reason set_property below no longer coerces to float:
# `set_property pause true` used to crash this peer, so the one shape the pause contract
# needs — a player paused by somebody else — could not be produced at all.
VALS = {"time-pos": 61.5, "duration": 245.0, "percent-pos": 25.1,
        "volume": float(opt("--vol", "55")), "pause": "--paused" in args}
try: os.unlink(sock_path)
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(sock_path); s.listen(5)

def serve(c):
    f = c.makefile("rwb")
    pending = []
    def flush_replies():
        if REVERSE: pending.reverse()
        for line in pending:
            if NOISY: f.write(b'{"event":"property-change","name":"noise"}\n')
            f.write(line); f.flush()
        pending.clear()
    if NOISY:
        f.write(b'{"event":"start-file"}\n'); f.flush()
    def timer():
        while True:
            threading.Event().wait(0.15)
            if pending:
                try: flush_replies()
                except Exception: return
    threading.Thread(target=timer, daemon=True).start()
    for raw in f:
        raw = raw.strip()
        if not raw: continue
        try: req = json.loads(raw)
        except Exception: continue
        cmd, rid = req.get("command", []), req.get("request_id", 0)
        data = None
        if cmd and cmd[0] == "get_property":
            data = None if cmd[1] in NULLS else VALS.get(cmd[1])
            if ADVANCE and cmd[1] in ("time-pos", "percent-pos") and data is not None:
                pos = VALS["time-pos"] + (time.time() - T0)
                data = pos if cmd[1] == "time-pos" else 100.0 * pos / VALS["duration"]
        elif cmd and cmd[0] == "set_property":
            VALS[cmd[1]] = cmd[2] if isinstance(cmd[2], bool) else float(cmd[2])
            with open(LOG, "a") as lg: lg.write("set %s=%s\n" % (cmd[1], cmd[2]))
        pending.append((json.dumps({"data": data, "request_id": rid, "error": "success"}) + "\n").encode())
        if not REVERSE: flush_replies()
        # REVERSE holds replies back and a timer releases them: nc never shuts its write half,
        # so waiting for request-stream EOF would mean waiting for the timeout under test.
        elif len(pending) >= 3: flush_replies()
    flush_replies()
    # never close first
while True:
    c, _ = s.accept(); threading.Thread(target=serve, args=(c,), daemon=True).start()
