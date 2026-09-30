import Foundation

/// SDK-independent policy used by the native platform view and executable tests.
/// No app key, coordinates or SDK objects are retained here.
final class KakaoEngineLifecycle {
  enum Stage: String {
    case platformViewCreated, sdkInitialized, enginePrepared, authenticating
    case authenticated, engineActivated, addViewsRequested, addViewSucceeded
    case loaded, failed
  }

  private(set) var stage = Stage.platformViewCreated
  private(set) var stages: [Stage] = [.platformViewCreated]
  let keyPresent: Bool
  private(set) var sdkInitialized = false
  private(set) var authenticated = false
  private(set) var engineActive = false
  private(set) var foreground: Bool
  private(set) var bounds: CGRect
  private(set) var viewAdded = false
  private(set) var loaded = false
  private(set) var failed = false
  private(set) var authErrorCode: Int?
  private(set) var retryCount = 0
  private(set) var retryDelay: TimeInterval?
  private var addViewsReceived = false
  private var viewRequested = false
  var onStage: ((Stage) -> Void)?

  init(keyPresent: Bool, foreground: Bool, bounds: CGRect) {
    self.keyPresent = keyPresent
    self.foreground = foreground
    self.bounds = bounds
  }

  var hasSize: Bool { bounds.width > 0 && bounds.height > 0 }
  var terminalFailure: Bool { failed && retryDelay == nil }

  func sdkDidInitialize() {
    sdkInitialized = true
    record(.sdkInitialized)
  }

  func prepareRequested() {
    failed = false
    retryDelay = nil
    record(.enginePrepared)
    record(.authenticating)
  }

  func authenticationSucceeded() {
    authenticated = true
    failed = false
    authErrorCode = nil
    retryDelay = nil
    record(.authenticated)
  }

  /// Two retries per platform-view lifetime; only communication error 499.
  /// Foreground changes do not replenish the budget.
  func authenticationFailed(_ code: Int) {
    authenticated = false
    engineActive = false
    viewAdded = false
    viewRequested = false
    addViewsReceived = false
    loaded = false
    failed = true
    authErrorCode = code
    if code == 499 && retryCount < 2 {
      retryDelay = retryCount == 0 ? 0.5 : 1.5
      retryCount += 1
    } else {
      retryDelay = nil
    }
    record(.failed)
  }

  func fail() {
    failed = true
    engineActive = false
    retryDelay = nil
    record(.failed)
  }

  func setForeground(_ value: Bool) {
    foreground = value
    if !value { engineActive = false }
  }

  func resize(_ value: CGRect) { bounds = value }

  /// Mark active before calling the SDK, which may immediately call addViews.
  func requestActivation() -> Bool {
    guard foreground, authenticated, hasSize, !failed, !engineActive else { return false }
    engineActive = true
    record(.engineActivated)
    return true
  }

  func addViews() {
    addViewsReceived = true
    record(.addViewsRequested)
  }

  func requestView() -> Bool {
    guard foreground, authenticated, engineActive, hasSize, !failed,
          addViewsReceived, !viewRequested, !viewAdded else { return false }
    viewRequested = true
    return true
  }

  func addViewSucceeded(currentBounds: CGRect) {
    bounds = currentBounds
    viewAdded = true
    record(.addViewSucceeded)
  }

  func markLoaded() -> Bool {
    guard foreground, authenticated, engineActive, viewAdded, hasSize,
          !failed, !loaded else { return false }
    loaded = true
    record(.loaded)
    return true
  }

  private func record(_ value: Stage) {
    stage = value
    stages.append(value)
    if stages.count > 24 { stages.removeFirst(stages.count - 24) }
    onStage?(value)
  }
}
