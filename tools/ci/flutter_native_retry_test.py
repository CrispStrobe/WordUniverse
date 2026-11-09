import contextlib
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import textwrap
import unittest


spec = importlib.util.spec_from_file_location(
    "flutter_native_retry", Path(__file__).with_name("flutter_native_retry.py")
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

MISMATCH = (
    "Bad state: Hash of downloaded file libsqlite3.x64.linux.so is "
    + "a" * 64
    + ", expected "
    + "b" * 64
    + ".\nBuilding native assets failed."
)


class NativeDownloadRetryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        previous = Path.cwd()
        os.chdir(self.project)
        self.addCleanup(os.chdir, previous)

    def run_fake(self, body, attempts=3):
        script = self.project / "fake_flutter.py"
        script.write_text(textwrap.dedent(body), encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(
            io.StringIO()
        ):
            return runner.run([sys.executable, str(script)], attempts=attempts, delay=0)

    def test_bad_download_is_rebuilt_and_verified_on_retry(self):
        broken = self.project / ".dart_tool/hooks_runner/shared/sqlite3/build/download-bad"
        broken.mkdir(parents=True)
        (broken / "libsqlite3.x64.linux.so").write_text("bad response")
        unrelated = self.project / ".dart_tool/hooks_runner/other/keep"
        unrelated.parent.mkdir(parents=True)
        unrelated.write_text("untouched")
        result = self.run_fake(
            f"""
            from pathlib import Path
            import sys
            counter = Path('attempts')
            counter.write_text(str(int(counter.read_text()) + 1) if counter.exists() else '1')
            if Path('.dart_tool/hooks_runner/shared/sqlite3').exists():
                print({MISMATCH!r})
                sys.exit(1)
            print('All tests passed!')
            """
        )
        self.assertEqual(result, 0)
        self.assertEqual(Path("attempts").read_text(), "2")
        self.assertEqual(unrelated.read_text(), "untouched")

    def test_a_real_test_failure_is_not_retried(self):
        result = self.run_fake(
            """
            from pathlib import Path
            import sys
            counter = Path('attempts')
            counter.write_text(str(int(counter.read_text()) + 1) if counter.exists() else '1')
            print('Some tests failed.')
            sys.exit(7)
            """
        )
        self.assertEqual(result, 7)
        self.assertEqual(Path("attempts").read_text(), "1")

    def test_a_persistent_checksum_mismatch_remains_a_failure(self):
        result = self.run_fake(
            f"""
            from pathlib import Path
            import sys
            counter = Path('attempts')
            counter.write_text(str(int(counter.read_text()) + 1) if counter.exists() else '1')
            print({MISMATCH!r})
            sys.exit(1)
            """
        )
        self.assertEqual(result, 1)
        self.assertEqual(Path("attempts").read_text(), "3")

    def test_never_removes_a_link_to_an_external_cache(self):
        external = self.project.parent / (self.project.name + "-external")
        external.mkdir()
        self.addCleanup(external.rmdir)
        target = self.project / ".dart_tool/hooks_runner/shared/sqlite3"
        target.parent.mkdir(parents=True)
        target.symlink_to(external, target_is_directory=True)
        self.assertEqual(runner.discard_sqlite_hook_cache(self.project), [])
        self.assertTrue(external.exists())

    def test_other_native_failures_are_not_matched(self):
        self.assertFalse(runner.is_retryable("Building native assets failed."))
        self.assertFalse(runner.is_retryable(MISMATCH + "\nSome tests failed."))


if __name__ == "__main__":
    unittest.main()
