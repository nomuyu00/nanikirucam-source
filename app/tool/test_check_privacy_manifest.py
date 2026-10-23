import plistlib
from pathlib import Path
import tempfile
import unittest
import zipfile

from check_privacy_manifest import artifact_tracking_problems, tracking_problems


class TrackingManifestTests(unittest.TestCase):
    def test_tracking_requires_domains_even_when_key_is_missing(self):
        # ビルド8の実際の組み合わせ。以前の検査が誤って受理していた。
        for app_root in (True, False):
            with self.subTest(app_root=app_root):
                self.assertTrue(tracking_problems({'NSPrivacyTracking': True}, 'manifest', app_root=app_root))

    def test_nontracking_may_omit_domains(self):
        self.assertEqual(tracking_problems({'NSPrivacyTracking': False}, 'app', app_root=True), [])

    def test_tracking_with_empty_sdk_domains_is_also_rejected(self):
        self.assertTrue(tracking_problems({'NSPrivacyTracking': True, 'NSPrivacyTrackingDomains': []}, 'sdk'))

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
                archive.writestr('Payload/Runner.app/PrivacyInfo.xcprivacy', plistlib.dumps({'NSPrivacyTracking': True, 'NSPrivacyTrackingDomains': ['ads.example.com']}))
                archive.writestr('Payload/Runner.app/Example.bundle/PrivacyInfo.xcprivacy', plistlib.dumps({'NSPrivacyTracking': False, 'NSPrivacyTrackingDomains': ['ads.example.com']}))
            issues = artifact_tracking_problems(ipa=ipa)
            self.assertEqual(len(issues), 1)
            self.assertIn('Example.bundle', issues[0])

    def test_actual_ipa_with_build8_missing_domains_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'build8.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/Runner.app/PrivacyInfo.xcprivacy', plistlib.dumps({'NSPrivacyTracking': True}))
            issues = artifact_tracking_problems(ipa=ipa)
            self.assertEqual(len(issues), 1)
            self.assertIn('NSPrivacyTracking=true', issues[0])

    def test_ipa_requires_own_manifest(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'sample.ipa'
            with zipfile.ZipFile(ipa, 'w'):
                pass
            self.assertTrue(artifact_tracking_problems(ipa=ipa))


if __name__ == '__main__':
    unittest.main()
