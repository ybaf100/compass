"""Source-boundary guards; native geometry and rendering have separate tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
SWIFT = (ROOT / "platform_overrides/ios/AppDelegate.swift").read_text()
KOTLIN = (ROOT / "platform_overrides/android/KakaoMapPlatformView.kt").read_text()


class KakaoMarkerContractTests(unittest.TestCase):
    def test_heading_updates_only_current_user(self):
        for source, start, end in (
            (SWIFT, "private func updateUserHeading", "private func startCameraHeadingWatch"),
            (KOTLIN, "private fun updateUserHeading", "private fun startCameraHeadingWatch"),
        ):
            body = source.split(start, 1)[1].split(end, 1)[0]
            self.assertIn('["user"]', body)
            for unrelated in ("applyMarkers(", "removePoi", "removeLabel", "setMembers", "setSharedPings"):
                self.assertNotIn(unrelated, body)

    def test_density_and_friend_interaction_preserved(self):
        self.assertIn(".setApplyDpScale(false)", KOTLIN)
        self.assertIn("bitmap.density = Bitmap.DENSITY_NONE", KOTLIN)
        self.assertIn("format.scale = 1", SWIFT)
        self.assertIn('.setClickable(id.startsWith("member:"))', KOTLIN)
        self.assertIn('options.clickable = id.hasPrefix("member:")', SWIFT)

    def test_unrelated_overlay_frames_do_not_cancel_heading_animation(self):
        for source, start, end in (
            (SWIFT, "private func applyMarkers", "private func updateUserHeading"),
            (KOTLIN, "private fun applyMarkers", "private fun updateUserHeading"),
        ):
            body = source.split(start, 1)[1].split(end, 1)[0]
            self.assertIn("userHeading != previousHeading || !userHasOrientation", body)
            self.assertNotIn("updateUserHeading(animated: false)", body)
            self.assertNotIn("updateUserHeading(false)", body)

    def test_prepare_return_remains_diagnostic_only(self):
        self.assertIn("lifecycle.prepareReturned(controller.prepareEngine())", SWIFT)
        self.assertNotIn("prepareEngine() == false", SWIFT)


if __name__ == "__main__":
    unittest.main()
