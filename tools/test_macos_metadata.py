"""Cross-platform checks for metadata required by Mac App Store validation."""
import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class MacMetadataTest(unittest.TestCase):
    def plist(self, path):
        with (ROOT / path).open('rb') as source:
            return plistlib.load(source)

    def test_learning_app_has_education_category(self):
        self.assertEqual(
            self.plist('macos/Runner/Info.plist')
            .get('LSApplicationCategoryType'),
            'public.app-category.education')

    def test_export_compliance_is_answered_in_the_bundle(self):
        # Without this key a build processes with usesNonExemptEncryption null,
        # and TestFlight refuses it to every tester — internal included — with
        # "422 Build is not assignable". macOS was missing it while iOS had it,
        # which is the likeliest reason MAC_OS build 5 was never distributed.
        # false is correct for an app using nothing beyond standard HTTPS/TLS.
        for path in ('macos/Runner/Info.plist', 'ios/Runner/Info.plist'):
            self.assertIs(
                self.plist(path).get('ITSAppUsesNonExemptEncryption'), False,
                f'{path} must answer export compliance')


if __name__ == '__main__':
    unittest.main()
