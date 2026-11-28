#!/usr/bin/env python3
"""Offline only: synthetic logs, fake credentials and fake Apple commands."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts/stream_regression_logs.py"
FAKE_SECRET = "synthetic-private-credential-NOT-REAL-51"
FAKE_BASE64 = "U1lOVEhFVElDX05PVF9SRUFMX0NSRURFTlRJQUw="
FAKE_API = "AIza" + "syntheticNotRealCredential" * 2


def eventually(predicate, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.03)
    raise AssertionError("synthetic snapshot condition timed out")


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="regression-offline-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.private = self.root / "private"
        self.output = self.root / "artifacts"
        self.private.mkdir()
        self.env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1", "GOOGLE_SERVICE_INFO_BASE64": FAKE_BASE64}
        (self.private / "redactions.json").write_text(json.dumps([FAKE_SECRET]), encoding="utf-8")

    def command(self, *extra):
        return [sys.executable, str(HELPER), "--private-dir", str(self.private),
                "--output-dir", str(self.output), "--interval", "0.05", *extra]

    def kill_and_reap(self, proc):
        if proc.poll() is None:
            try:
                proc.kill()
            except ProcessLookupError:
                pass
        proc.communicate(timeout=5)

    def start(self, *extra):
        proc = subprocess.Popen(self.command(*extra), env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(self.kill_and_reap, proc)
        return proc

    def stop(self, proc, sig=signal.SIGTERM):
        if proc.poll() is None:
            try:
                proc.send_signal(sig)
            except ProcessLookupError:
                pass
        try:
            out, err = proc.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            if proc.poll() is None:
                try:
                    proc.kill()
                except ProcessLookupError:
                    pass
            proc.communicate(timeout=5)
            self.fail("snapshot worker exceeded 30s graceful-stop budget; killed and reaped")
        self.assertEqual(proc.returncode, 0, (out, err))
        self.assertEqual(out + err, b"")

    def text(self, name):
        path = self.output / name
        return path.read_text(encoding="utf-8") if path.exists() else ""

    def diagnostic(self):
        return json.loads(self.text("regression-diagnostics.json") or "{}")

    def hashes(self):
        return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in self.private.iterdir() if p.is_file()}

    def test_live_per_suite_before_producer_completion_and_unchanged_inputs(self):
        producer = subprocess.Popen([sys.executable, "-c",
            "import pathlib,sys,time; p=pathlib.Path(sys.argv[1]); "
            "(p/'test.log').write_text(sys.argv[2],encoding='utf-8'); "
            "(p/'ready').touch(); time.sleep(30)", str(self.private),
            "preparation compiler evidence\n" + FAKE_SECRET + "\n" + FAKE_BASE64 + "\n" + FAKE_API + "\n" + "safe padding\n" * 20],
            env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(self.kill_and_reap, producer)
        eventually(lambda: (self.private / "ready").exists())
        (self.private / "ipad-test.log").write_text("iPad compiler assertion evidence\n" + FAKE_SECRET + "\n" + "padding\n" * 20)
        (self.private / "phone-test.log").write_text("iPhone independent evidence\n" + FAKE_API + "\n" + "padding\n" * 20)
        statuses = "MEDIA51_IPAD_EXIT_STATUS=65\nMEDIA51_IPHONE_EXIT_STATUS=running\n"
        (self.private / "media51-exit-status.txt").write_text(statuses)
        (self.private / "regression-phase.txt").write_text("phone-test\n")
        before = self.hashes()
        proc = self.start()
        eventually(lambda: "iPhone independent evidence" in self.text("media51-phone-test.log"))
        # Diagnostics is atomically committed after all log and exit-status files.
        # Seeing the phone log alone does not mean the same snapshot is complete.
        eventually(lambda: self.diagnostic().get("phase") == "phone-test")
        self.assertIsNone(proc.poll())
        self.assertIsNone(producer.poll(), "evidence must precede producer completion")
        self.assertIn("preparation compiler evidence", self.text("regressions.log"))
        self.assertIn("iPad compiler assertion evidence", self.text("media51-ipad-test.log"))
        self.assertNotIn("iPhone independent", self.text("media51-ipad-test.log"))
        self.assertEqual(self.text("media51-exit-status.txt"), statuses)
        self.assertEqual(self.diagnostic()["phase"], "phone-test")
        for _ in range(30):
            self.assertIn("heartbeat_utc", self.diagnostic())  # atomic JSON replacement
        self.stop(proc)
        producer.terminate()
        producer.wait(timeout=5)
        self.assertEqual(self.hashes(), before, "private source files must not change")
        for path in self.output.iterdir():
            text = path.read_text(encoding="utf-8")
            for secret in (FAKE_SECRET, FAKE_BASE64, FAKE_API):
                self.assertNotIn(secret, text)
        self.assertTrue(self.diagnostic()["final"])

    def test_missing_partial_xml_utf8_and_signal_flush(self):
        for sig in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=sig):
                # The preceding signal subcase leaves a final diagnostic behind.
                # Require a fresh process snapshot before signaling this child.
                (self.output / "regression-diagnostics.json").unlink(missing_ok=True)
                source = self.private / "test.log"
                source.unlink(missing_ok=True)
                proc = self.start("--max-read-bytes", "1024")
                eventually(lambda: self.diagnostic().get("logs", {}).get("test.log", {}).get("state") == "not-created")
                source.write_bytes(b"visible first\n<?xml version='1.0'?>\n<plist>\n<key>PRIVATE_XML_VALUE</key>\n")
                eventually(lambda: self.diagnostic().get("logs", {}).get("test.log", {}).get("read_bytes", 0) > 0)
                self.assertNotIn("PRIVATE_XML_VALUE", self.text("regressions.log"))
                self.assertNotIn("<plist", self.text("regressions.log"))
                with source.open("ab") as stream:
                    stream.write(b"</plist>\n" + "完整中文🙂\n".encode("utf-8") + b"\xff\nunfinished-" + FAKE_SECRET[:10].encode())
                self.stop(proc, sig)
                text = self.text("regressions.log")
                self.assertIn("已隐藏 plist 正文", text)
                self.assertIn("完整中文🙂", text)
                self.assertIn("\ufffd", text)
                self.assertNotIn("unfinished-", text)
                self.assertNotIn("PRIVATE_XML_VALUE", text)

    def test_bounds_oversize_rotation_and_fail_closed_manifest(self):
        source = self.private / "test.log"
        source.write_text("a" * 12000)
        proc = self.start("--max-read-bytes", "1024", "--max-output-bytes", "1024")
        eventually(lambda: self.diagnostic().get("logs", {}).get("test.log", {}).get("omitted_records", 0) > 0)
        with source.open("a") as stream:
            stream.write("\n" + "recovered compiler evidence\n" * 10)
        eventually(lambda: "recovered compiler evidence" in self.text("regressions.log"))
        self.assertLessEqual((self.output / "regressions.log").stat().st_size, 1100)
        source.write_text("rotated assertion evidence\n" * 20)
        eventually(lambda: "rotated assertion evidence" in self.text("regressions.log"))
        old = self.text("regressions.log")
        (self.private / "redactions.json").write_text("{incomplete")
        with source.open("a") as stream:
            stream.write(FAKE_SECRET + "\nnot safe until manifest repaired\n" * 5)
        eventually(lambda: "snapshot_error" in self.diagnostic())
        self.assertEqual(self.text("regressions.log"), old)
        (self.private / "redactions.json").write_text(json.dumps([FAKE_SECRET]))
        eventually(lambda: "not safe until manifest repaired" in self.text("regressions.log"))
        self.stop(proc)
        self.assertNotIn(FAKE_SECRET, self.text("regressions.log"))

    def test_read_boundary_utf8_and_multiline_credentials(self):
        multiline = "synthetic-multiline-first\nsynthetic-multiline-second"
        (self.private / "redactions.json").write_text(json.dumps([FAKE_SECRET, multiline]))
        source = self.private / "test.log"
        # UTF-8 starts at byte 1023; the scalar and later credentials cross reads.
        source.write_bytes(b"p" * 1022 + b"\n" + "中文🙂\n".encode() +
                           (FAKE_SECRET + "\n" + multiline + "\n" + FAKE_API + "\n" + "padding\n" * 100).encode())
        proc = self.start("--max-read-bytes", "1024")
        eventually(lambda: self.diagnostic().get("logs", {}).get("test.log", {}).get("backlog_bytes") == 0)
        self.stop(proc)
        text = self.text("regressions.log")
        self.assertIn("中文🙂", text)
        self.assertNotIn("\ufffd", text)
        for value in (FAKE_SECRET, FAKE_API, "synthetic-multiline-first", "synthetic-multiline-second"):
            self.assertNotIn(value, text)
        source.write_text("safe prefix\nsynthetic-multiline-first\n")
        subprocess.run(self.command("--once"), env=self.env, check=True, capture_output=True)
        self.assertIn("safe prefix", self.text("regressions.log"))
        self.assertNotIn("synthetic-multiline-first", self.text("regressions.log"))

    def test_status_only_preserves_log_tail_and_records_exit(self):
        (self.private / "test.log").write_text("existing compiler tail\n")
        subprocess.run(self.command("--once"), env=self.env, check=True, capture_output=True)
        before = self.text("regressions.log")
        (self.private / "test.log").write_text("must not replace existing tail\n")
        (self.private / "regression-phase.txt").write_text("cancelled-term\n")
        (self.private / "regression-exit-status.txt").write_text("143\n")
        (self.private / "media51-exit-status.txt").write_text("MEDIA51_IPAD_EXIT_STATUS=65\nMEDIA51_IPHONE_EXIT_STATUS=cancelled\n")
        subprocess.run(self.command("--status-only"), env=self.env, check=True, capture_output=True)
        self.assertEqual(self.text("regressions.log"), before)
        self.assertEqual(self.diagnostic()["exit_status"], 143)
        self.assertEqual(self.diagnostic()["phase"], "cancelled-term")
        self.assertIn("IPAD_EXIT_STATUS=65", self.text("media51-exit-status.txt"))


class ScriptIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fake-native-regression-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.scripts = self.root / "scripts"
        self.scripts.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.root / "runner-temp").mkdir()
        for name in ("test_qingyun_regressions.sh", "stream_regression_logs.py", "prepare_trollstore_test.py"):
            shutil.copyfile(ROOT / "scripts" / name, self.scripts / name)
        self.executable(self.bin / "uname", "#!/bin/sh\necho Darwin\n")
        self.executable(self.bin / "xcrun", "#!/bin/sh\nexit 1\n")
        self.executable(self.bin / "python3", "#!/bin/sh\n"
            "if [ \"$1\" = scripts/prepare_trollstore_test.py ]; then\n"
            " case \"$2\" in prepare) echo synthetic-preparation-evidence; exit 0;; select-xcode) echo /fake-xcode; exit 0;; esac\nfi\n"
            f"exec '{sys.executable}' \"$@\"\n")
        (self.scripts / "ensure_metal_toolchain.sh").write_text("echo synthetic-metal-evidence\n")
        (self.scripts / "sim.sh").write_text("echo id=fake-simulator\n")
        self.executable(self.bin / "xcodebuild", f"#!{sys.executable}\n" +
            "import os,sys,time\n"
            "if '-resolvePackageDependencies' in sys.argv:\n print('synthetic-package-evidence'); sys.exit(0)\n"
            "selectors=[a for a in sys.argv if a.startswith('-only-testing:')]\n"
            "phone='-only-testing:yuedu appUITests/CodaBottomBarUITests' in selectors\n"
            "if phone:\n"
            " assert selectors == ['-only-testing:yuedu appUITests/CodaBottomBarUITests', '-only-testing:yuedu appUITests/CodaProviderSearchUITests']\n"
            "else:\n"
            " assert selectors == [\n"
            "  '-only-testing:yuedu appTests/AddedFilmRemovalTests',\n"
            "  '-only-testing:yuedu appTests/RemovedVideoUIBoundaryTests',\n"
            "  '-only-testing:yuedu appTests/CodaMusicHostIntegrationTests',\n"
            "  '-only-testing:yuedu appTests/CodaAggregateSongSearchModelFixtureTests',\n"
            "  '-only-testing:yuedu appTests/CodaExplicitNetEaseSearchTransportFixtureTests',\n"
            "  '-only-testing:yuedu appTests/CodaSearchInteractionPolicyTests',\n"
            "  '-only-testing:yuedu appTests/MediaHubInteractionTests',\n"
            "  '-only-testing:yuedu appTests/SourceImportPlanTests',\n"
            "  '-only-testing:yuedu appTests/MediaTabMenuTests',\n"
            "  '-only-testing:yuedu appTests/RootTabCustomizationTests',\n"
            "  '-only-testing:yuedu appTests/ReadccBackdropBlurTests',\n"
            "  '-only-testing:yuedu appUITests/CodaIPadNavigationUITests',\n"
            "  '-only-testing:yuedu appUITests/CodaProviderSearchUITests',\n"
            " ]\n"
            "print('synthetic-phone-evidence' if phone else 'synthetic-ipad-evidence',flush=True)\n"
            "if os.environ.get('FAKE_WAIT') == '1':\n"
            " open(os.environ['FAKE_READY'],'w').close(); time.sleep(30)\n"
            "code=int(os.environ.get('FAKE_PHONE_EXIT' if phone else 'FAKE_IPAD_EXIT','0'))\n"
            "print('** TEST SUCCEEDED **' if code==0 and os.environ.get('FAKE_OMIT_MARKER') != '1' else 'synthetic assertion failed')\n"
            "sys.exit(code)\n")
        self.env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1", "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                    "GITHUB_ACTIONS": "true", "QINGYUN_REGRESSION_SCOPE": "media51",
                    "RUNNER_TEMP": str(self.root / "runner-temp"), "GOOGLE_SERVICE_INFO_BASE64": FAKE_BASE64}

    def executable(self, path, text):
        path.write_text(text)
        path.chmod(0o700)

    def run_script(self, **env):
        command = ["bash", "scripts/test_qingyun_regressions.sh"]
        proc = subprocess.Popen(command, cwd=self.root, env={**self.env, **env},
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True)
        try:
            # This synthetic harness also runs on an emulated, contended iOS
            # shell. Keep a finite infrastructure budget; no assertion changes.
            out, err = proc.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            # Reap the complete fake-runner group, not only its Bash parent;
            # orphan snapshot workers would contaminate later timing checks.
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
            raise
        return subprocess.CompletedProcess(command, proc.returncode, out, err)

    def test_retired_film_scopes_fail_before_preparation(self):
        for scope in ("catvod-home", "md5-import"):
            with self.subTest(scope=scope):
                result = self.run_script(QINGYUN_REGRESSION_SCOPE=scope)
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn(b"RETIRED", result.stderr)
                self.assertNotIn(b"TEST SUCCEEDED", result.stdout + result.stderr)
                self.assertFalse((self.root / "trollstore-output").exists())

    def test_retired_native_importer_produces_no_historical_verdict_or_artifact(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/verify_readcc49_native.py")],
            cwd=self.root, env=self.env, capture_output=True, timeout=5,
        )
        self.assertEqual(result.returncode, 64, result.stderr)
        self.assertIn(b"RETIRED", result.stderr)
        self.assertNotIn(b"PASS", result.stdout + result.stderr)
        self.assertFalse((self.root / "trollstore-output").exists())

    def test_ipad_failure_still_runs_phone_and_preserves_independent_exit_codes(self):
        result = self.run_script(FAKE_IPAD_EXIT="65", FAKE_PHONE_EXIT="0")
        self.assertEqual(result.returncode, 1, result.stderr)
        output = self.root / "trollstore-output"
        self.assertIn("synthetic-ipad-evidence", (output / "media51-ipad-test.log").read_text())
        self.assertIn("synthetic-phone-evidence", (output / "media51-phone-test.log").read_text())
        self.assertEqual((output / "media51-exit-status.txt").read_text(),
                         "MEDIA51_IPAD_EXIT_STATUS=65\nMEDIA51_IPHONE_EXIT_STATUS=0\n")
        self.assertEqual(json.loads((output / "regression-diagnostics.json").read_text())["exit_status"], 1)
        self.assertEqual(list((self.root / "runner-temp").iterdir()), [])

    def test_both_success_and_unchanged_success_marker_assertion(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b"** TEST SUCCEEDED **", result.stdout)
        self.assertIn("IPHONE_EXIT_STATUS=0", (self.root / "trollstore-output/media51-exit-status.txt").read_text())

    def test_phone_failure_and_missing_success_marker_are_not_hidden(self):
        result = self.run_script(FAKE_PHONE_EXIT="66")
        self.assertEqual(result.returncode, 1)
        statuses = (self.root / "trollstore-output/media51-exit-status.txt").read_text()
        self.assertEqual(statuses, "MEDIA51_IPAD_EXIT_STATUS=0\nMEDIA51_IPHONE_EXIT_STATUS=66\n")
        # A fresh private tree is used on every invocation; zero tool exit alone
        # must never bypass the original per-suite TEST SUCCEEDED assertions.
        result = self.run_script(FAKE_OMIT_MARKER="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"missing successful test marker", result.stderr)

    def test_term_cancellation_retains_live_evidence_and_cancelled_status(self):
        self.assert_cancellation(signal.SIGTERM, 143, "cancelled-term")

    def test_int_cancellation_retains_live_evidence_and_cancelled_status(self):
        self.assert_cancellation(signal.SIGINT, 130, "cancelled-int")

    def assert_cancellation(self, sig, code, phase):
        ready = self.root / "active-test"
        proc = subprocess.Popen(["bash", "scripts/test_qingyun_regressions.sh"], cwd=self.root,
                                env={**self.env, "FAKE_WAIT": "1", "FAKE_READY": str(ready)},
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: proc.kill() if proc.poll() is None else None)
        eventually(ready.exists)
        output = self.root / "trollstore-output"
        eventually(lambda: (output / "regressions.log").exists())
        self.assertIsNone(proc.poll())
        proc.send_signal(sig)
        out, err = proc.communicate(timeout=12)
        self.assertEqual(proc.returncode, code, (out, err))
        self.assertIn("synthetic-ipad-evidence", (output / "media51-ipad-test.log").read_text())
        self.assertEqual((output / "media51-exit-status.txt").read_text(),
                         "MEDIA51_IPAD_EXIT_STATUS=cancelled\nMEDIA51_IPHONE_EXIT_STATUS=not_started\n")
        diagnostic = json.loads((output / "regression-diagnostics.json").read_text())
        self.assertEqual(diagnostic["phase"], phase)
        self.assertEqual(diagnostic["exit_status"], code)
        self.assertEqual(list((self.root / "runner-temp").iterdir()), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
