"""Cross-platform checks for metadata required by Mac App Store validation."""
import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class MacMetadataTest(unittest.TestCase):
    def test_learning_app_has_education_category(self):
        with (ROOT / 'macos/Runner/Info.plist').open('rb') as source:
            metadata = plistlib.load(source)
        self.assertEqual(metadata.get('LSApplicationCategoryType'),
                         'public.app-category.education')


if __name__ == '__main__':
    unittest.main()
