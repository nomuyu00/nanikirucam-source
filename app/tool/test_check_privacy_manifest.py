import plistlib
from pathlib import Path
import tempfile
import unittest
import zipfile

from check_privacy_manifest import artifact_tracking_problems, tracking_problems


class TrackingManifestTests(unittest.TestCase):
    def test_app_omits_unused_domains_without_changing_tracking(self):
        self.assertEqual(tracking_problems({'NSPrivacyTracking': True}, 'app', app_root=True), [])

    def test_empty_app_domains_rejected_for_both_tracking_values(self):
        for flag in (True, False):
            with self.subTest(flag=flag):
                self.assertTrue(tracking_problems({'NSPrivacyTracking': flag, 'NSPrivacyTrackingDomains': []}, 'app', app_root=True))

    def test_nonempty_domains_require_explicit_tracking(self):
        for flag in (False, None):
            with self.subTest(flag=flag):
                self.assertTrue(tracking_problems({'NSPrivacyTracking': flag, 'NSPrivacyTrackingDomains': ['ads.example.com']}, 'sdk'))
        self.assertEqual(tracking_problems({'NSPrivacyTracking': True, 'NSPrivacyTrackingDomains': ['ads.example.com']}, 'sdk'), [])

    def test_sdk_empty_domains_are_not_rewritten(self):
        self.assertEqual(tracking_problems({'NSPrivacyTracking': False, 'NSPrivacyTrackingDomains': []}, 'sdk'), [])

    def test_invalid_domain_type_is_rejected(self):
        self.assertTrue(tracking_problems({'NSPrivacyTracking': True, 'NSPrivacyTrackingDomains': 'ads.example.com'}, 'sdk'))
        self.assertTrue(tracking_problems({'NSPrivacyTracking': True, 'NSPrivacyTrackingDomains': ['']}, 'sdk'))

    def test_actual_ipa_entries_are_inspected(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'sample.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/Runner.app/PrivacyInfo.xcprivacy', plistlib.dumps({'NSPrivacyTracking': True}))
                archive.writestr('Payload/Runner.app/Example.bundle/PrivacyInfo.xcprivacy', plistlib.dumps({'NSPrivacyTracking': False, 'NSPrivacyTrackingDomains': ['ads.example.com']}))
            issues = artifact_tracking_problems(ipa=ipa)
            self.assertEqual(len(issues), 1)
            self.assertIn('Example.bundle', issues[0])

    def test_ipa_requires_own_manifest(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'sample.ipa'
            with zipfile.ZipFile(ipa, 'w'):
                pass
            self.assertTrue(artifact_tracking_problems(ipa=ipa))


if __name__ == '__main__':
    unittest.main()
