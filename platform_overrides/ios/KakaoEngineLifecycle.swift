import Foundation
import CoreGraphics

/// SDK-independent policy used by the native platform view and executable tests.
/// No app key, coordinates or SDK objects are retained here.
final class KakaoEngineLifecycle {
  enum Stage: String {
    case platformViewCreated, sdkInitialized, enginePrepareRequested, authenticating
    case enginePrepared, authenticated, engineActivationRequested, engineActivated
    case addViewsRequested, addViewSucceeded, loaded, prepareTimedOut, timedOut, failed
  }
  enum AuthCallback: String { case none, succeeded, failed }
  enum TimeoutFailure: String { case prepareTimeout, timeout }
  static let timeoutSeconds: TimeInterval = 18

  private(set) var stage = Stage.platformViewCreated
  private(set) var stages: [Stage] = [.platformViewCreated]
  let keyPresent: Bool
  private(set) var sdkInitialized = false
  private(set) var authenticated = false
  private(set) var authCallback = AuthCallback.none
  private(set) var enginePrepared = false
  private(set) var engineActive = false
  private(set) var prepareReturn: Bool?
  private(set) var timeoutFailure: TimeoutFailure?
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
  private var activationRequested = false
  private var preparedThisAttempt = false
  var onStage: ((Stage) -> Void)?

  init(keyPresent: Bool, foreground: Bool, bounds: CGRect) {
    self.keyPresent = keyPresent
    self.foreground = foreground
    self.bounds = bounds
  }

  var hasSize: Bool { bounds.size.width > 0 && bounds.size.height > 0 }
  var terminalFailure: Bool { failed && retryDelay == nil }

  func sdkDidInitialize() {
    sdkInitialized = true
    record(.sdkInitialized)
  }

  func prepareRequested() {
    failed = false
    retryDelay = nil
    timeoutFailure = nil
    prepareReturn = nil
    authCallback = .none
    activationRequested = false
    preparedThisAttempt = false
    record(.enginePrepareRequested)
    record(.authenticating)
  }

  /// The SDK does not document false as a terminal failure. Diagnostic only.
  func prepareReturned(_ result: Bool) { prepareReturn = result }

  /// Values come from KMController, never inferred from method return values.
  func observeEngine(prepared: Bool, active: Bool) {
    let becamePrepared = prepared && !enginePrepared
    let becameActive = active && !engineActive
    enginePrepared = prepared
    engineActive = active
    if prepared || active { preparedThisAttempt = true }
    if active { activationRequested = false }
    if !failed {
      if becamePrepared { record(.enginePrepared) }
      if becameActive { record(.engineActivated) }
    }
  }

  func authenticationSucceeded() {
    authenticated = true
    authCallback = .succeeded
    failed = false
    authErrorCode = nil
    retryDelay = nil
    timeoutFailure = nil
    record(.authenticated)
  }

  /// Shared budget for actual 499 callbacks and prepare timeouts only.
  /// Foreground changes do not replenish the budget.
  func authenticationFailed(_ code: Int) {
    authenticated = false
    authCallback = .failed
    viewAdded = false
    viewRequested = false
    addViewsReceived = false
    loaded = false
    failed = true
    authErrorCode = code
    activationRequested = false
    scheduleRetry(recoverable: code == 499)
    record(.failed)
  }

  private func scheduleRetry(recoverable: Bool) {
    if recoverable && retryCount < 2 {
      retryDelay = retryCount == 0 ? 0.5 : 1.5
      retryCount += 1
    } else {
      retryDelay = nil
    }
  }

  /// Called by a bounded foreground deadline, not by prepareEngine's Bool.
  /// Auth/addViews/prepared progress separates preparation from rendering.
  func deadlineReached(elapsed: TimeInterval) -> TimeoutFailure? {
    guard elapsed >= Self.timeoutSeconds, foreground, !loaded, !failed else { return nil }
    let reason: TimeoutFailure = !preparedThisAttempt && authCallback == .none && !addViewsReceived
        ? .prepareTimeout : .timeout
    timeoutFailure = reason
    failed = true
    activationRequested = false
    scheduleRetry(recoverable: reason == .prepareTimeout)
    record(reason == .prepareTimeout ? .prepareTimedOut : .timedOut)
    return reason
  }

  /// SDK debug text has no documented privacy-safe schema. Retain only its
  /// presence; summary words are derived from authoritative booleans/callbacks.
  func sanitizedStateDescription(_ raw: String) -> (available: Bool, summary: String) {
    (!raw.isEmpty, engineStateSummary)
  }

  var engineStateSummary: String {
    if failed { return retryDelay == nil ? "failed" : "recovering" }
    if engineActive { return "active" }
    if enginePrepared { return "prepared" }
    return sdkInitialized ? "preparing" : "notCreated"
  }

  func fail() {
    failed = true
    retryDelay = nil
    activationRequested = false
    record(.failed)
  }

  func setForeground(_ value: Bool) {
    foreground = value
    if !value { activationRequested = false }
  }

  func resize(_ value: CGRect) { bounds = value }

  /// Official drawing samples do not require an auth-success callback before
  /// activation. Prepared SDK state also permits it (e.g. cached auth).
  func requestActivation() -> Bool {
    guard foreground, hasSize, !failed, !engineActive, !activationRequested,
          enginePrepared || authenticated else { return false }
    activationRequested = true
    record(.engineActivationRequested)
    return true
  }

  func addViews() {
    addViewsReceived = true
    record(.addViewsRequested)
  }

  func requestView() -> Bool {
    guard foreground, hasSize, !failed,
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
    guard foreground, engineActive, viewAdded, hasSize,
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
