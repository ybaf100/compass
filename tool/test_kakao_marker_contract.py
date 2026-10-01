"""Source-boundary guards; native geometry and rendering have separate tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
SWIFT = (ROOT / "platform_overrides/ios/AppDelegate.swift").read_text()
KOTLIN = (ROOT / "platform_overrides/android/KakaoMapPlatformView.kt").read_text()
ORIENTATION = (ROOT / "platform_overrides/ios/HeadingOrientation.swift").read_text()


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

    def test_user_absolute_rotation_and_single_camera_compensation(self):
        self.assertIn("options.transformType = .absoluteRotation", SWIFT)
        self.assertIn('if (id == "user") TransformMethod.AbsoluteRotation else TransformMethod.Default', KOTLIN)
        self.assertIn('if id == "user" {', SWIFT)
        for source in (SWIFT, KOTLIN):
            self.assertEqual(source.count("KakaoMarkerGeometry.display("), 1)
            self.assertNotIn("Default supplies a screen-up", source)

    def test_scale_changes_styles_not_native_map_or_overlays(self):
        swift = SWIFT.split('case "markerScale":', 1)[1].split('case "camera":', 1)[0]
        kotlin = KOTLIN.split('"markerScale" -> {', 1)[1].split('"camera" -> {', 1)[0]
        self.assertIn("poi.changeStyle", swift)
        self.assertIn("label.setStyles", kotlin)
        for body in (swift, kotlin):
            for forbidden in ("prepareEngine", "activateEngine", "applyMarkers(", "removePoi", "removeLabel"):
                self.assertNotIn(forbidden, body)

    def test_artwork_zero_points_up_and_dot_is_symmetric(self):
        self.assertIn('arrow.move(to: CGPoint(x: 0, y: -17))', SWIFT)
        self.assertIn('moveTo(0f, -17f)', KOTLIN)
        self.assertIn('canvas.drawCircle(0f, 0f', KOTLIN)
        self.assertIn('CGRect(x: -diameter/2, y: -diameter/2', SWIFT)

    def test_ipad_interface_orientation_is_not_replaced_by_device_orientation(self):
        self.assertIn('switch scene?.interfaceOrientation', SWIFT)
        self.assertIn('case .landscapeLeft: return .landscapeRight', ORIENTATION)
        self.assertIn('case .landscapeRight: return .landscapeLeft', ORIENTATION)
        self.assertIn('case .portrait: return .portrait', ORIENTATION)
        self.assertIn('case .portraitUpsideDown: return .portraitUpsideDown', ORIENTATION)
        self.assertIn('let changed = orientation.update(snapshot)', SWIFT)
        self.assertIn('switch orientation.applied', SWIFT)
        self.assertNotIn('UIDevice.current.orientation', SWIFT)
        self.assertIn('default: snapshot = .unknown', SWIFT)

    def test_heading_refreshes_initial_rotation_and_foreground_without_polling(self):
        bridge = SWIFT.split('private final class HeadingBridge', 1)[1]
        resume = bridge.split('@objc private func resume()', 1)[1].split('@objc private func pause()', 1)[0]
        self.assertLess(resume.index('orientationChanged()'), resume.index('startUpdatingHeading()'))
        for notification in ('UIDevice.orientationDidChangeNotification',
                             'UIApplication.didBecomeActiveNotification',
                             'UIScene.didActivateNotification'):
            self.assertIn(notification, bridge)
        self.assertIn('for delay in [0.15, 0.5]', bridge)
        self.assertNotIn('Timer', bridge)
        self.assertIn('orientationRefreshWork.forEach { $0.cancel() }', bridge)
        self.assertIn('if refreshOrientation() { return }', bridge)
        self.assertIn('heading.timestamp < appliedAt', bridge)

    def test_heading_diagnostics_are_enum_only_and_angles_have_no_offsets(self):
        bridge = SWIFT.split('private final class HeadingBridge', 1)[1]
        self.assertIn('"interfaceOrientation": orientation.interface.rawValue', bridge)
        self.assertIn('"headingOrientation": orientation.applied.rawValue', bridge)
        self.assertIn('"heading": trueNorth ? heading.trueHeading : heading.magneticHeading', bridge)
        self.assertNotIn('heading.trueHeading +', bridge)
        self.assertNotIn('heading.trueHeading -', bridge)
        self.assertNotIn('latitude', bridge)
        self.assertNotIn('longitude', bridge)

    def test_prepare_return_remains_diagnostic_only(self):
        self.assertIn("lifecycle.prepareReturned(controller.prepareEngine())", SWIFT)
        self.assertNotIn("prepareEngine() == false", SWIFT)


if __name__ == "__main__":
    unittest.main()
