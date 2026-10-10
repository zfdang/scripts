"""Parser and subprocess integration tests, without sending network probes."""
import csv
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "vultr-test.py"
spec = importlib.util.spec_from_file_location("vultr_test", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NetworkTests(unittest.TestCase):
    def test_linux_and_macos_statistics(self):
        for label in ("rtt min/avg/max/mdev", "round-trip min/avg/max/stddev"):
            stats = module.parse_ping(
                f"5 packets transmitted, 4 received, 20% packet loss\n{label} = 1.1/2.2/3.3/0.4 ms"
            )
            self.assertEqual(stats["loss_percent"], "20")
            self.assertEqual(stats["avg_ms"], "2.2")
            self.assertEqual(stats["max_ms"], "3.3")

    def test_unreachable_has_no_invented_latency(self):
        stats = module.parse_ping("5 packets transmitted, 0 packets received, 100.0% packet loss")
        self.assertEqual(stats["loss_percent"], "100.0")
        self.assertEqual(stats["avg_ms"], "")

    def test_selection_rejects_unknown_and_deduplicates(self):
        nodes = module.load_nodes()
        self.assertEqual(len(module.select_nodes(nodes, "sgp,Singapore")), 1)
        with self.assertRaises(ValueError):
            module.select_nodes(nodes, "SGP,nonexistent")

    def test_timeout_preserves_partial_log(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "trace.txt"
            status = module.run_logged(
                [sys.executable, "-u", "-c", "import time; print('first hop'); time.sleep(10)"],
                log, 0.2,
            )
            self.assertEqual(status, "timeout")
            self.assertIn("first hop", log.read_text())

    def test_ping_failure_does_not_skip_routes_or_later_nodes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ping = root / "ping"
            ping.write_text('''#!/bin/sh
case "$*" in
*45.32.100.168*) echo '3 packets transmitted, 0 received, 100% packet loss'; exit 1 ;;
esac
echo '3 packets transmitted, 3 received, 0% packet loss'
echo 'rtt min/avg/max/mdev = 10.0/20.0/30.0/1.0 ms'
''')
            nt = root / "nt"
            nt.write_text('''#!/bin/sh
if [ "$1" = --help ]; then echo '--traceroute'; exit 0; fi
printf '%s\\n' "$*"
echo 'hop 1 -> hop 2 -> destination'
''')
            ping.chmod(0o755)
            nt.chmod(0o755)
            output = root / "results"
            result = subprocess.run([
                sys.executable, str(SCRIPT), "--location", "SGP,NRT", "--count", "3",
                "--output", str(output),
            ], capture_output=True, text=True,
                env={**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"]})
            self.assertEqual(result.returncode, 1, result.stderr)
            with (output / "summary.csv").open() as file:
                rows = list(csv.DictReader(file))
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]["ping_status"], "exit_1")
            self.assertEqual(rows[0]["trace_status"], "ok")
            self.assertEqual(rows[1]["avg_ms"], "20.0")
            self.assertIn("--traceroute", (output / "SGP-route.txt").read_text())
            self.assertIn("45.32.100.168", (output / "SGP-route.txt").read_text())
            self.assertIn("108.61.201.151", (output / "NRT-route.txt").read_text())


if __name__ == "__main__":
    unittest.main()
