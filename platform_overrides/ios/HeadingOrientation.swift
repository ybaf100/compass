/// SDK-independent conversion used by the CoreLocation bridge, not angle math.
/// UIKit names UI rotation; CoreLocation names physical device orientation.
/// Apple: https://developer.apple.com/documentation/uikit/uiinterfaceorientation
enum HeadingOrientationName: String {
  case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight

  var coreLocationOrientation: HeadingOrientationName? {
    switch self {
    case .portrait: return .portrait
    case .portraitUpsideDown: return .portraitUpsideDown
    case .landscapeLeft: return .landscapeRight
    case .landscapeRight: return .landscapeLeft
    case .unknown: return nil
    }
  }
}

struct HeadingOrientationState {
  private(set) var interface: HeadingOrientationName = .unknown
  private(set) var applied: HeadingOrientationName = .portrait

  /// A missing/transitional scene must not overwrite the last valid reference.
  /// Returns true only when CoreLocation's reference frame needs to change.
  @discardableResult mutating func update(_ snapshot: HeadingOrientationName) -> Bool {
    interface = snapshot
    guard let next = snapshot.coreLocationOrientation else { return false }
    let changed = next != applied
    applied = next
    return changed
  }
}
