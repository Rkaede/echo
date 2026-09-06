"""Offline macOS release checks: python3 -m unittest discover -s scripts/tests -v."""

import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


class UpdateVerificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.workspace.cleanup)
        cls.directory = Path(cls.workspace.name)
        cls.verifier = cls.directory / "verify-update"
        subprocess.run(
            ["xcrun", "swiftc", str(ROOT / "scripts/verify-update.swift"), "-o", str(cls.verifier)],
            check=True, capture_output=True, text=True,
        )
        # Deterministic test-only key and payload; no signing credentials are accessed.
        fixture = subprocess.run(["xcrun", "swift", "-"], input='''
import CryptoKit
import Foundation
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 7, count: 32))
let payload = Data("installer fixture".utf8)
let values = ["key": key.publicKey.rawRepresentation.base64EncodedString(),
              "signature": try key.signature(for: payload).base64EncodedString()]
print(String(data: try JSONSerialization.data(withJSONObject: values), encoding: .utf8)!)
''', check=True, capture_output=True, text=True)
        cls.signing = json.loads(fixture.stdout)

    def setUp(self):
        self.archive = self.directory / "Echo.dmg"
        self.archive.write_bytes(b"installer fixture")
        self.info = self.directory / "Info.plist"
        self.info.write_bytes(plistlib.dumps({
            "CFBundleVersion": "3", "CFBundleShortVersionString": "0.0.3",
            "SUPublicEDKey": self.signing["key"],
        }))
        self.feed = ET.fromstring(f'''<rss xmlns:sparkle="{SPARKLE}"><channel><item>
<sparkle:version>3</sparkle:version><sparkle:shortVersionString>0.0.3</sparkle:shortVersionString>
<enclosure url="https://github.com/Rkaede/echo/releases/download/v0.0.3/Echo.dmg"
length="17" sparkle:edSignature="{self.signing['signature']}"/>
</item></channel></rss>''')

    def verify(self):
        appcast = self.directory / "appcast.xml"
        ET.ElementTree(self.feed).write(appcast)
        return subprocess.run(
            [str(self.verifier), str(appcast), str(self.info), str(self.archive)],
            capture_output=True, text=True,
        )

    def test_accepts_matching_installer(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_changed_bytes_even_when_length_matches(self):
        self.archive.write_bytes(b"Installer fixture")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signature", result.stderr)

    def test_rejects_wrong_length(self):
        self.feed.find("./channel/item/enclosure").set("length", "18")
        self.assertIn("size mismatch", self.verify().stderr)

    def test_rejects_wrong_version(self):
        self.feed.find(f"./channel/item/{{{SPARKLE}}}version").text = "2"
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_wrong_download_url(self):
        self.feed.find("./channel/item/enclosure").set("url", "https://example.com/Echo.dmg")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_rejects_duplicate_build(self):
        channel = self.feed.find("channel")
        channel.append(ET.fromstring(ET.tostring(channel.find("item"))))
        self.assertNotEqual(self.verify().returncode, 0)


class ReleasePublicationTests(unittest.TestCase):
    def run_release(self, failure="", answers="0.0.3\nyyyy"):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            (workspace / "CHANGELOG.md").write_text("## Echo 0.0.3\n\nUpdate fixes.\n")
            # Exercise the real main() sequencing. All build, signing and remote
            # actions are replaced, so these tests cannot publish anything.
            harness = '''
source "$ECHO_TEST_REPO/scripts/release.sh"
PROJECT_DIR="$ECHO_TEST_WORKSPACE"
EXPORT_DIR="$PROJECT_DIR"
trace() { echo "$*" >> "$PROJECT_DIR/trace"; }
load_env_file() { :; }
check_prerequisites() { CURRENT_BRANCH=main; }
get_current_version() { echo 0.0.2; }
update_version() { :; }
clean_build() { :; }
build_app() { :; }
archive_app() { :; }
export_app() { :; }
create_dmg() { echo fixture > "$EXPORT_DIR/Echo-$1.dmg"; }
generate_release_notes_html() { :; }
notarize_app() { trace notarize; }
update_appcast() { trace sign; }
verify_update() { trace verify-local; [[ "$ECHO_TEST_FAILURE" != local ]]; }
commit_and_tag() { trace commit-and-tag; }
git() { trace "git $*"; }
create_github_release() { trace upload; [[ "$ECHO_TEST_FAILURE" != upload ]]; }
verify_published_update() { trace verify-remote; [[ "$ECHO_TEST_FAILURE" != remote ]]; }
main
'''
            result = subprocess.run(["bash", "-c", harness], input=answers,
                capture_output=True, text=True, env={**os.environ,
                    "ECHO_TEST_REPO": str(ROOT), "ECHO_TEST_WORKSPACE": directory,
                    "ECHO_TEST_FAILURE": failure})
            trace = (workspace / "trace").read_text().splitlines()
            return result, [step for step in trace if not step.startswith("git describe")]

    def test_verifies_download_before_publishing_feed(self):
        result, trace = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace, ["notarize", "sign", "verify-local", "commit-and-tag",
            "git push origin v0.0.3", "upload", "verify-remote", "git push origin main"])

    def test_failure_prevents_feed_publication(self):
        for failure in ("local", "upload", "remote"):
            with self.subTest(failure=failure):
                result, trace = self.run_release(failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("git push origin main", trace)

    def test_declining_publication_does_not_push(self):
        result, trace = self.run_release(answers="0.0.3\nyyyn")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(step.startswith("git push") for step in trace))
        self.assertIn("have not been published", result.stdout)


if __name__ == "__main__":
    unittest.main()
