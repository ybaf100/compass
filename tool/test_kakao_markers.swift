import Foundation

@main struct KakaoMarkerTests {
  static var passed = 0
  static func test(_ name: String, _ body: () -> Void) {
    body(); passed += 1; print("PASS: \(name)")
  }
  static func main() {
    test("north-up east heading") { precondition(KakaoMarkerGeometry.display(heading: 90, cameraBearing: 0) == 90) }
    test("rotated map compensates") { precondition(KakaoMarkerGeometry.display(heading: 90, cameraBearing: 45) == 45) }
    test("map bearing change and wrapping") { precondition(KakaoMarkerGeometry.display(heading: 0, cameraBearing: 359) == 1) }
    test("359 to zero uses +1") { precondition(KakaoMarkerGeometry.target(from: 359, to: 0) == 360) }
    test("zero to 359 uses -1") { precondition(KakaoMarkerGeometry.target(from: 0, to: 359) == -1) }
    test("continuous turn retains unwrapped progress") { precondition(KakaoMarkerGeometry.target(from: 719, to: 0) == 720) }
    test("destination and smaller peer markers") {
      precondition(KakaoMarkerGeometry.diameter("destination") == 22)
      for kind in ["member", "stale", "ping"] { precondition(KakaoMarkerGeometry.diameter(kind) == 18) }
      precondition(KakaoMarkerGeometry.diameter("candidate") == 16)
    }
    test("small visible peers retain transparent touch area") {
      for kind in ["member", "stale"] { precondition(KakaoMarkerGeometry.canvas(kind) == 44) }
    }
    test("direction canvas is centered on a small GPS dot") {
      precondition(KakaoMarkerGeometry.userDot == 16 && KakaoMarkerGeometry.canvas("userHeading") == 40)
      precondition(KakaoMarkerGeometry.canvas("user") == KakaoMarkerGeometry.canvas("userHeading"))
    }
    print("Kakao native marker geometry: \(passed) tests passed")
  }
}
