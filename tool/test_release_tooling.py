"""Icon bootstrap regression and bounded iPad smoke recovery tests."""

from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import app_icons
import run_ipad_smoke_test as smoke


class ReleaseToolingTests(unittest.TestCase):
    def test_icon_catalog_dimensions_and_opacity(self):
        app_icons.verify()

    def test_repeated_icon_bootstrap_preserves_artwork(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'android/app/src/main').mkdir(parents=True)
            (root / 'ios/Runner/Assets.xcassets').mkdir(parents=True)
            with patch.object(app_icons, 'ROOT', root):
                app_icons.apply()
                app_icons.apply()
                app_icons.verify(applied=True)
                icon = root / 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png'
                icon.write_bytes(b'wrong icon')
                with self.assertRaises(ValueError):
                    app_icons.verify(applied=True)

    def run_smoke(self, results):
        devices = '{"devices":{"runtime":[{"name":"iPad","udid":"test-device","state":"Shutdown"}]}}'
        with patch.object(smoke.subprocess, 'check_output', return_value=devices), \
             patch.object(smoke.subprocess, 'run') as native, \
             patch.object(smoke, 'run_attempt', side_effect=results) as attempt:
            code = smoke.main()
            return code, attempt.call_count, native.call_args_list

    def test_smoke_success_is_not_retried(self):
        code, count, _ = self.run_smoke([(0, False)])
        self.assertEqual((code, count), (0, 1))

    def test_actual_test_failure_is_not_retried(self):
        code, count, _ = self.run_smoke([(1, False)])
        self.assertEqual((code, count), (1, 1))

    def test_launch_timeout_retries_once_without_erasing_device(self):
        code, count, commands = self.run_smoke([(124, True), (0, False)])
        self.assertEqual((code, count), (0, 2))
        self.assertTrue(any('shutdown' in call.args[0] for call in commands))
        self.assertFalse(any('erase' in call.args[0] for call in commands))

    def test_launch_retry_budget_is_bounded(self):
        code, count, _ = self.run_smoke([(124, True), (124, True)])
        self.assertEqual((code, count), (124, 2))


if __name__ == '__main__':
    unittest.main()
