@main struct HeadingOrientationTests {
  static var passed = 0
  static func test(_ name: String, _ body: () -> Void) {
    body(); passed += 1; print("PASS: \(name)")
  }
  static func main() {
    for (interface, expected) in [
      (HeadingOrientationName.portrait, HeadingOrientationName.portrait),
      (.portraitUpsideDown, .portraitUpsideDown),
      (.landscapeLeft, .landscapeRight),
      (.landscapeRight, .landscapeLeft)
    ] {
      test("UI \(interface.rawValue) converts to CL \(expected.rawValue)") {
        var state = HeadingOrientationState()
        state.update(interface)
        precondition(state.interface == interface && state.applied == expected)
      }
    }
    test("unknown initial scene keeps CoreLocation portrait default") {
      var state = HeadingOrientationState()
      precondition(!state.update(.unknown) && state.applied == .portrait)
    }
    test("launch in landscape does not require a device notification") {
      var state = HeadingOrientationState()
      precondition(state.update(.landscapeLeft) && state.applied == .landscapeRight)
    }
    test("portrait to both landscapes and back updates each reference") {
      var state = HeadingOrientationState()
      for (interface, expected) in [
        (HeadingOrientationName.landscapeLeft, HeadingOrientationName.landscapeRight),
        (.landscapeRight, .landscapeLeft), (.portrait, .portrait)
      ] {
        precondition(state.update(interface) && state.applied == expected)
      }
    }
    test("repeated interface snapshot does not reset the sensor frame") {
      var state = HeadingOrientationState()
      state.update(.landscapeRight)
      precondition(!state.update(.landscapeRight) && state.applied == .landscapeLeft)
    }
    test("missing scene during background retains last applied landscape") {
      var state = HeadingOrientationState()
      state.update(.landscapeLeft)
      precondition(!state.update(.unknown) && state.applied == .landscapeRight)
      precondition(state.interface == .unknown)
    }
    test("foreground fresh scene snapshot restores changed orientation") {
      var state = HeadingOrientationState()
      state.update(.landscapeLeft); state.update(.unknown)
      precondition(state.update(.landscapeRight) && state.applied == .landscapeLeft)
    }
    test("locked UI snapshot wins over physical device changes") {
      var state = HeadingOrientationState()
      state.update(.portrait)
      precondition(!state.update(.portrait) && state.applied == .portrait)
    }
    test("unlock and committed scene orientation updates reference") {
      var state = HeadingOrientationState()
      state.update(.portrait)
      precondition(state.update(.landscapeRight) && state.applied == .landscapeLeft)
    }
    test("upside down to landscape changes reference without angle offsets") {
      var state = HeadingOrientationState()
      state.update(.portraitUpsideDown)
      precondition(state.update(.landscapeLeft) && state.applied == .landscapeRight)
    }
    print("iOS production heading orientation: \(passed) tests passed")
  }
}
