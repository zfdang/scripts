"""Verify executable replacement without touching the installed service."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "trojan-go.sh").read_text()
FUNCTION = SOURCE[SOURCE.index("replaceTrojanBinary() {"):SOURCE.index("\ninstallTrojan() {")]


class BinaryReplacementTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.target = self.root / "trojan-go"
        self.source = self.root / "new-binary"
        compiler = shutil.which("cc")
        if not compiler:
            self.skipTest("a C compiler is required for the running executable fixture")
        fixture = self.root / "sleep.c"
        fixture.write_text('#include <unistd.h>\nint main(int argc, char **argv) {\n'
                           'if (argc > 1 && argv[1][0] != \'0\') sleep(60); return 0; }\n')
        subprocess.run([compiler, str(fixture), "-o", str(self.source)],
                       check=True, capture_output=True)
        shutil.copy(self.source, self.target)

    def replace(self, mocks=""):
        return subprocess.run(
            ["bash", "-c", FUNCTION + "\n" + mocks +
             '\nreplaceTrojanBinary "$1" "$2"', "test",
             str(self.source), str(self.target)], capture_output=True, text=True,
        )

    def test_running_executable_is_replaced_without_stopping_process(self):
        process = subprocess.Popen([str(self.target), "60"])
        try:
            inode = self.target.stat().st_ino
            result = self.replace()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIsNone(process.poll())
            self.assertNotEqual(inode, self.target.stat().st_ino)
            self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
            self.assertEqual(self.target.stat().st_mode & 0o777, 0o755)
            subprocess.run([str(self.target), "0"], check=True)
            self.assertEqual(list(self.root.glob("trojan-go.*")), [])
        finally:
            process.terminate()
            process.wait()

    def test_staging_failure_preserves_old_binary_and_cleans_up(self):
        original = self.target.read_bytes(), self.target.stat().st_ino
        result = self.replace('cp() { printf partial > "$2"; return 1; }')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(original, (self.target.read_bytes(), self.target.stat().st_ino))
        self.assertEqual(list(self.root.glob("trojan-go.*")), [])

    def test_rename_failure_preserves_old_binary_and_cleans_up(self):
        inode = self.target.stat().st_ino
        result = self.replace('mv() { return 1; }')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(inode, self.target.stat().st_ino)
        self.assertEqual(list(self.root.glob("trojan-go.*")), [])


if __name__ == "__main__":
    unittest.main()
