import Foundation

/// Camera compensation uses the native camera during a gesture, never a stale
/// Dart snapshot. Angles here are clockwise degrees from screen-up.
enum KakaoMarkerGeometry {
  static let userCanvas = 40.0
  static let userDot = 16.0
  static let memberTouchCanvas = 44.0
  static func diameter(_ kind: String) -> Double {
    switch kind {
    case "destination": return 22
    case "member", "stale", "ping": return 18
    case "user", "userHeading": return userDot
    default: return 16
    }
  }
  static func canvas(_ kind: String) -> Double {
    if kind == "user" || kind == "userHeading" { return userCanvas }
    if kind == "member" || kind == "stale" { return memberTouchCanvas }
    return diameter(kind) + 4
  }
  static func normalize(_ degrees: Double) -> Double {
    let result = degrees.truncatingRemainder(dividingBy: 360)
    return result < 0 ? result + 360 : result
  }
  static func display(heading: Double, cameraBearing: Double) -> Double {
    normalize(heading - cameraBearing)
  }
  static func target(from current: Double, to desired: Double) -> Double {
    current + normalize(desired - current + 180) - 180
  }
}
