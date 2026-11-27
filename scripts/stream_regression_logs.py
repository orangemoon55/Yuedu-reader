#!/usr/bin/env python3
"""Bounded, local-only regression snapshots. Never publish a private raw log.

Uses the packaging redactor unchanged; this is NOT a general secret detector.
Only complete lines/closed plist records are published. Oversize records are
omitted rather than truncated into potentially unredactable credential fragments.
"""
import signal

# Register before importing the packaging module or parsing arguments: a runner
# can cancel immediately after spawning us, including under CPU contention.
_interrupted = False


def early_stop(*_):
    global _interrupted
    _interrupted = True


for _signal in (signal.SIGTERM, signal.SIGINT):
    signal.signal(_signal, early_stop)

import argparse
import codecs
import json
import os
from pathlib import Path
import re
import stat
import tempfile
import threading
import time

SOURCES = {
    "test.log": "regressions.log",
    "ipad-test.log": "media51-ipad-test.log",
    "phone-test.log": "media51-phone-test.log",
}
PHASES = {
    "starting", "preparing", "select-xcode", "metal-toolchain", "destination-ipad",
    "destination", "resolve-packages", "ipad-test",
    "destination-phone", "phone-test", "test", "verify-results", "finishing",
    "cancelled-term", "cancelled-int", "finished",
}
OPEN_XML = re.compile(r"<\?xml\b|<plist\b")
MAX_SECRET = 128 * 1024
MAX_MANIFEST = 512 * 1024


def atomic_write(path, text):
    # The temporary artifact contains sanitized text only, is bounded and replaced
    # on the same filesystem. Readers see the old or new complete snapshot.
    fd, name = tempfile.mkstemp(prefix=".regression-snapshot-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read_regular(path, limit, offset=0):
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise ValueError("not a regular log")
        stream.seek(offset)
        return stream.read(limit), info


class Log:
    def __init__(self):
        self.offset = 0
        self.identity = None
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.pending = ""
        self.safe = ""
        self.skipping = None
        self.omitted = 0
        self.available = 0
        self.error = None

    def update(self, source, secrets, sanitize, read_limit, output_limit, final):
        try:
            raw, info = read_regular(source, read_limit, self.offset)
            identity = (info.st_dev, info.st_ino)
            if self.identity != identity or info.st_size < self.offset:
                self.offset = 0
                self.pending = ""
                self.skipping = None
                self.decoder.reset()
                raw, info = read_regular(source, read_limit)
                if self.identity is not None:
                    self.safe += "\n[snapshot: source replaced/truncated]\n"
            self.identity = identity
            self.offset += len(raw)
            self.available = max(0, info.st_size - self.offset)
            self.error = None
        except FileNotFoundError:
            self.error = "not-created"
            return
        except (OSError, ValueError):
            self.error = "unreadable"
            return
        self.pending += self.decoder.decode(raw)
        if self.skipping:
            marker = "</plist>" if self.skipping == "plist" else "\n"
            end = self.pending.find(marker)
            if end < 0:
                self.pending = self.pending[-len(marker):]
                return
            self.pending = self.pending[end + len(marker):]
            self.skipping = None
        # Hold a known-secret-length lookahead, and never cut a known multiline
        # value or XML record in half before passing it to the existing redactor.
        guard = 0 if final and not self.available else max(map(len, secrets), default=0)
        cut = self.pending.rfind("\n", 0, max(0, len(self.pending) - guard) + 1) + 1
        for value in secrets:
            start = self.pending.find(value, max(0, cut - len(value) + 1))
            if 0 <= start < cut < start + len(value):
                cut = start
            if final:
                prefix = ""
                for line in value.splitlines(keepends=True)[:-1]:
                    prefix += line
                    if prefix and self.pending[:cut].endswith(prefix):
                        cut -= len(prefix)
        xml_start = None
        position = 0
        while True:
            opening = OPEN_XML.search(self.pending, position)
            if not opening or opening.start() >= cut:
                break
            closing = self.pending.find("</plist>", opening.end())
            if closing < 0 or closing + 8 > cut:
                xml_start = opening.start()
                cut = xml_start
                break
            position = closing + 8
        if cut:
            self.safe += sanitize(self.pending[:cut])
            self.pending = self.pending[cut:]
        if len(self.pending.encode("utf-8")) > read_limit * 2:
            # Keep no fragment of an overlong line or open plist. Resume only
            # after its terminator; a marker records the intentional omission.
            self.skipping = "plist" if xml_start is not None or OPEN_XML.search(self.pending) else "line"
            self.pending = self.pending[-16:]
            self.omitted += 1
            self.safe += "\n[snapshot: oversized/incomplete record omitted]\n"
        self.safe = self.safe.encode("utf-8")[-output_limit:].decode("utf-8", errors="replace")


class Snapshots:
    def __init__(self, private, output, read_limit, output_limit):
        self.private, self.output = private, output
        self.read_limit, self.output_limit = read_limit, output_limit
        self.logs = {name: Log() for name in SOURCES}
        self.count = 0
        self.output.mkdir(parents=True, exist_ok=True)
        os.environ["TROLLSTORE_PRIVATE_DIR"] = str(private)

    def secrets(self):
        try:
            data, info = read_regular(self.private / "redactions.json", MAX_MANIFEST + 1)
        except FileNotFoundError:
            hidden = []
        else:
            if info.st_size > MAX_MANIFEST:
                raise ValueError("redaction manifest too large")
            hidden = json.loads(data.decode("utf-8"))
        if not isinstance(hidden, list) or len(hidden) > 128 or not all(isinstance(v, str) for v in hidden):
            raise ValueError("invalid redaction manifest")
        encoded = os.environ.get("GOOGLE_SERVICE_INFO_BASE64", "")
        hidden += [encoded, re.sub(r"\s+", "", encoded)]
        if any(len(v) > MAX_SECRET for v in hidden):
            raise ValueError("redaction value too large")
        return [v for v in hidden if v]

    def snapshot(self, final=False, status_only=False):
        self.count += 1
        diagnostic = {"snapshot": self.count, "heartbeat_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                      "final": final, "phase": "starting", "logs": {}}
        if status_only:
            try:
                previous, _ = read_regular(self.output / "regression-diagnostics.json", 16384)
                previous = json.loads(previous)
                diagnostic["snapshot"] = int(previous["snapshot"]) + 1
                for source in SOURCES:
                    entry = previous.get("logs", {}).get(source, {})
                    diagnostic["logs"][source] = {key: value for key, value in entry.items()
                        if (key in {"read_bytes", "backlog_bytes", "pending_characters", "omitted_records"}
                            and isinstance(value, int) and value >= 0)
                        or (key == "state" and value in {"not-created", "unreadable", "readable"})}
            except (OSError, ValueError, KeyError, TypeError, AttributeError):
                pass
        try:
            code, _ = read_regular(self.private / "regression-exit-status.txt", 8)
            if re.fullmatch(rb"[0-9]{1,3}\n", code):
                diagnostic["exit_status"] = int(code)
        except (OSError, ValueError):
            pass
        try:
            phase, _ = read_regular(self.private / "regression-phase.txt", 64)
            phase = phase.decode("ascii").strip()
            if phase in PHASES:
                diagnostic["phase"] = phase
        except (OSError, ValueError, UnicodeError):
            pass
        try:
            secrets = self.secrets()
            with tempfile.TemporaryDirectory(prefix="snapshot-redact-", dir=self.private) as scratch:
                raw_path, safe_path = Path(scratch) / "raw", Path(scratch) / "safe"

                def sanitize(text):
                    from prepare_trollstore_test import redact
                    raw_path.write_text(text, encoding="utf-8")
                    redact(raw_path, safe_path)
                    return safe_path.read_text(encoding="utf-8")

                for source, target in (() if status_only else SOURCES.items()):
                    state = self.logs[source]
                    state.update(self.private / source, secrets, sanitize, self.read_limit, self.output_limit, final)
                    atomic_write(self.output / target, "[bounded sanitized snapshot; see regression-diagnostics.json]\n" + state.safe)
                    diagnostic["logs"][source] = {"read_bytes": state.offset, "backlog_bytes": state.available,
                        "pending_characters": len(state.pending), "omitted_records": state.omitted, "state": state.error or "readable"}
                try:
                    raw_status, _ = read_regular(self.private / "media51-exit-status.txt", 512)
                    statuses = raw_status.decode("ascii").splitlines()
                    if len(statuses) != 2 or any(not re.fullmatch(r"MEDIA51_(?:IPAD|IPHONE)_EXIT_STATUS=(?:not_started|running|cancelled|[0-9]{1,3})", line) for line in statuses):
                        raise ValueError("invalid status")
                    atomic_write(self.output / "media51-exit-status.txt", sanitize("\n".join(statuses) + "\n"))
                except FileNotFoundError:
                    pass
        except Exception:
            # Fail closed: keep the previous sanitized artifacts, never print an
            # exception that might contain a raw secret or credential path.
            diagnostic["snapshot_error"] = "redaction-or-io-failed; previous sanitized snapshot retained"
        atomic_write(self.output / "regression-diagnostics.json", json.dumps(diagnostic, indent=2) + "\n")
        return "snapshot_error" not in diagnostic


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--interval", type=float, default=5)
    parser.add_argument("--max-read-bytes", type=int, default=4 * 1024 * 1024)
    parser.add_argument("--max-output-bytes", type=int, default=2 * 1024 * 1024)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--status-only", action="store_true", help="refresh final metadata without replacing log snapshots")
    args = parser.parse_args()
    if not (0.05 <= args.interval <= 60 and 1024 <= args.max_read_bytes <= 8 * 1024 * 1024 and
            1024 <= args.max_output_bytes <= 8 * 1024 * 1024):
        parser.error("snapshot limits outside supported bounds")
    private, output = args.private_dir.resolve(), args.output_dir.resolve()
    if private == output or private in output.parents or output in private.parents:
        parser.error("private and artifact directories must be separate")
    stopped = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: stopped.set())
    if _interrupted:
        stopped.set()
    snapshots = Snapshots(private, output, args.max_read_bytes, args.max_output_bytes)
    if args.once or args.status_only:
        return 0 if snapshots.snapshot(final=True, status_only=args.status_only) else 1
    snapshots.snapshot()
    while not stopped.wait(args.interval):
        snapshots.snapshot()
    # Bounded final catch-up; SIGKILL can still only preserve the last heartbeat.
    for _ in range(4):
        snapshots.snapshot(final=True)
        if not any(log.available for log in snapshots.logs.values()):
            break
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
