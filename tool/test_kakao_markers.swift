import Foundation

@main struct KakaoMarkerTests {
  static var passed = 0
  static func test(_ name: String, _ body: () -> Void) {
    body(); passed += 1; print("PASS: \(name)")
  }
  static func main() {
    test("north-up north points up") { precondition(KakaoMarkerGeometry.display(heading: 0, cameraBearing: 0) == 0) }
    test("camera east device east points up") { precondition(KakaoMarkerGeometry.display(heading: 90, cameraBearing: 90) == 0) }
    test("camera east device north points left") { precondition(KakaoMarkerGeometry.display(heading: 0, cameraBearing: 90) == 270) }
    test("camera east device south points right") { precondition(KakaoMarkerGeometry.display(heading: 180, cameraBearing: 90) == 90) }
    test("iOS final orientation is counterclockwise radians") { precondition(KakaoMarkerGeometry.orientationRadians(90) == -.pi / 2) }
    test("scale clamps and 125 percent preset") {
      precondition(KakaoMarkerGeometry.scale(0) == 0.5)
      precondition(KakaoMarkerGeometry.scale(3) == 2)
      precondition(KakaoMarkerGeometry.scale(1.25) == 1.25)
    }
    test("all scales preserve member touch canvas and hierarchy") {
      for scale in [0.5, 1, 1.25, 2] {
        for kind in ["member", "stale"] {
          precondition(KakaoMarkerGeometry.canvas(kind, scale: scale) >= 44)
          precondition(KakaoMarkerGeometry.diameter(kind) * scale < KakaoMarkerGeometry.diameter("destination") * scale)
        }
        precondition(KakaoMarkerGeometry.canvas("userHeading", scale: scale) == 40 * scale)
      }
    }
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
