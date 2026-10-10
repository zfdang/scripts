"""Exercise certificate lifecycle without installing packages or touching services."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "trojan-go.sh"
SOURCE = SCRIPT.read_text()
FUNCTIONS = SOURCE[SOURCE.index("colorEcho() {"):SOURCE.rindex("\ncheckSystem\n")]


class CertificateLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.cert = self.root / "server.pem"
        self.key = self.root / "server.key"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-days", "2", "-subj", "/CN=example.com", "-keyout", str(self.key),
            "-out", str(self.cert),
        ], check=True, capture_output=True)
        acme_home = self.root / "acme"
        (acme_home / "example.com_ecc").mkdir(parents=True)
        (acme_home / "example.com_ecc/example.com.conf").touch()
        acme = acme_home / "acme.sh"
        acme.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$TEST_ROOT/acme.log"
case "$1" in
    --install-cronjob) exit "${CRON_RESULT:-0}" ;;
    --renew) exit "${RENEW_RESULT:-0}" ;;
    --issue) exit "${ISSUE_RESULT:-1}" ;;
    --install-cert)
        while [[ $# -gt 0 ]]; do
            if [[ "$1" = --reloadcmd ]]; then eval "$2"; exit $?; fi
            shift
        done
        exit 1 ;;
esac
''')
        acme.chmod(0o700)
        (self.root / "config.json").write_text(
            '{\n"sni": "example.com",\n'
            f'"cert": "{self.cert}",\n"key": "{self.key}"\n}}\n'
        )

    def run_shell(self, command, **env):
        setup = '''
CONFIG_FILE="$TEST_ROOT/config.json"
CERT_FILE="$TEST_ROOT/server.pem"
KEY_FILE="$TEST_ROOT/server.key"
ACME_HOME="$TEST_ROOT/acme"
ACME_SH="$ACME_HOME/acme.sh"
DOMAIN=example.com
PMT=apt
CMD_INSTALL=true
colorEcho() { :; }
systemctl() {
    printf '%s\\n' "$*" >> "$TEST_ROOT/systemctl.log"
    if [[ "$*" = 'restart trojan-go.service' ]]; then return "${RESTART_RESULT:-0}"; fi
    if [[ "$*" = 'is-active --quiet trojan-go.service' ]]; then return "${ACTIVE_RESULT:-0}"; fi
}
export -f systemctl
crontab() {
    [[ "${MISSING_CRON:-0}" = 0 ]] || return 1
    printf '0 0 * * * "%s/acme.sh" --cron --home "%s"\\n' "$ACME_HOME" "$ACME_HOME"
}
configureTrojanService() { :; }
'''
        return subprocess.run(
            ["bash", "-c", FUNCTIONS + setup + command], text=True,
            capture_output=True,
            env={**os.environ, "TEST_ROOT": str(self.root), **env},
        )

    def test_deployment_restarts_and_checks_service(self):
        result = self.run_shell("setupCertRenewal")
        self.assertEqual(result.returncode, 0, result.stderr)
        acme_log = (self.root / "acme.log").read_text()
        self.assertIn("--install-cronjob", acme_log)
        self.assertIn(f"--fullchain-file {self.cert}", acme_log)
        log = (self.root / "systemctl.log").read_text()
        self.assertIn("start cron", log)
        self.assertIn("restart trojan-go.service\nis-active --quiet trojan-go.service", log)
        self.assertEqual(self.key.stat().st_mode & 0o777, 0o600)

    def test_missing_cron_entry_is_failure(self):
        result = self.run_shell("setupCertRenewal", MISSING_CRON="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("--install-cert", (self.root / "acme.log").read_text())

    def test_cron_install_failure_is_propagated(self):
        self.assertNotEqual(self.run_shell("setupCertRenewal", CRON_RESULT="1").returncode, 0)

    def test_restart_failure_is_propagated(self):
        self.assertNotEqual(self.run_shell("setupCertRenewal", RESTART_RESULT="1").returncode, 0)

    def test_inactive_service_is_failure(self):
        self.assertNotEqual(self.run_shell("setupCertRenewal", ACTIVE_RESULT="1").returncode, 0)

    def test_not_due_is_success_but_renewal_error_is_failure(self):
        self.assertEqual(self.run_shell("renewCert", RENEW_RESULT="2").returncode, 0)
        self.assertNotEqual(self.run_shell("renewCert", RENEW_RESULT="1").returncode, 0)

    def test_reconfiguration_preserves_certificate(self):
        original = self.cert.read_bytes(), self.key.read_bytes()
        result = self.run_shell("getCert")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(original, (self.cert.read_bytes(), self.key.read_bytes()))

    def test_mismatched_private_key_is_rejected(self):
        subprocess.run(["openssl", "genrsa", "-out", str(self.key), "2048"],
                       check=True, capture_output=True)
        self.assertNotEqual(self.run_shell("getCert").returncode, 0)

    def test_failed_issuance_restores_nginx_without_stopping_trojan(self):
        result = self.run_shell("""
unset CERT_FILE KEY_FILE
BT=false
stopNginx() { echo stop >> "$TEST_ROOT/nginx.log"; }
startNginx() { echo start >> "$TEST_ROOT/nginx.log"; }
ss() { echo 'LISTEN 0 128 *:443 *:*'; }
getCert
""")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / "nginx.log").read_text(), "stop\nstart\n")
        # Port 443 must not prevent the HTTP-01 attempt on port 80.
        self.assertIn("--issue", (self.root / "acme.log").read_text())
        self.assertNotIn("stop trojan", (self.root / "systemctl.log").read_text())

    def test_port_80_conflict_aborts_before_issuance(self):
        result = self.run_shell("""
unset CERT_FILE KEY_FILE
BT=false
stopNginx() { :; }
startNginx() { :; }
ss() { echo 'LISTEN 0 128 *:80 *:*'; }
getCert
""")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "acme.log").exists())

    def test_manual_certificate_cannot_claim_automatic_renewal(self):
        (self.root / "acme/example.com_ecc/example.com.conf").unlink()
        self.assertEqual(self.run_shell("setupCertRenewal").returncode, 0)
        self.assertNotEqual(self.run_shell("renewCert").returncode, 0)
        self.assertFalse((self.root / "acme.log").exists())


if __name__ == "__main__":
    unittest.main()
