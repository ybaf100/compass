import Foundation
import CoreGraphics

@main
struct KakaoLifecycleTests {
  static var passed = 0

  static func test(_ name: String, _ body: () -> Void) {
    body()
    passed += 1
    print("PASS: \(name)")
  }

  static func make(size: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
                   foreground: Bool = true) -> KakaoEngineLifecycle {
    let lifecycle = KakaoEngineLifecycle(keyPresent: true, foreground: foreground, bounds: size)
    lifecycle.sdkDidInitialize()
    lifecycle.prepareRequested()
    return lifecycle
  }

  static func activate(_ value: KakaoEngineLifecycle) {
    precondition(value.requestActivation())
    // Fake SDK state after activation, rather than inferring it from a call.
    value.observeEngine(prepared: true, active: true)
  }

  static func finishView(_ value: KakaoEngineLifecycle) {
    value.addViews()
    precondition(value.requestView())
    value.addViewSucceeded(currentBounds: value.bounds)
    precondition(value.markLoaded())
  }

  static func main() {
    test("auth success -> activate -> addViews -> loaded") {
      let value = make()
      precondition(!value.requestActivation())
      value.authenticationSucceeded()
      activate(value)
      precondition(!value.requestActivation(), "Do not activate twice")
      value.addViews()
      precondition(value.requestView())
      precondition(!value.requestView(), "Stable single view")
      value.addViewSucceeded(currentBounds: value.bounds)
      precondition(value.markLoaded())
      precondition(!value.markLoaded(), "Single loaded callback")
      precondition(value.stages == [.platformViewCreated, .sdkInitialized,
        .enginePrepareRequested, .authenticating, .authenticated,
        .engineActivationRequested, .enginePrepared, .engineActivated,
        .addViewsRequested, .addViewSucceeded, .loaded])
    }
    for code in [400, 401, 403, 429] {
      test("auth \(code) is terminal; foreground cannot retry/activate") {
        let value = make()
        value.authenticationFailed(code)
        precondition(value.authErrorCode == code)
        precondition(value.terminalFailure && value.retryDelay == nil)
        for _ in 0..<5 {
          value.setForeground(false)
          value.setForeground(true)
          precondition(!value.requestActivation())
          precondition(value.retryDelay == nil && value.retryCount == 0)
        }
      }
    }
    test("499 retries are bounded and resume cannot refill the budget") {
      let value = make()
      value.authenticationFailed(499)
      precondition(value.retryCount == 1 && value.retryDelay == 0.5)
      precondition(!value.terminalFailure)
      value.prepareRequested()
      value.authenticationFailed(499)
      precondition(value.retryCount == 2 && value.retryDelay == 1.5)
      value.prepareRequested()
      value.authenticationFailed(499)
      precondition(value.terminalFailure && value.retryDelay == nil)
      value.setForeground(false)
      value.setForeground(true)
      precondition(value.retryCount == 2 && value.retryDelay == nil)
    }
    test("background before auth success; foreground after success activates") {
      let value = make()
      value.setForeground(false)
      value.authenticationSucceeded()
      precondition(value.authenticated && !value.requestActivation())
      value.setForeground(true)
      activate(value)
    }
    test("pause preserves authentication without activating in background") {
      let value = make()
      value.authenticationSucceeded()
      activate(value)
      value.setForeground(false)
      value.observeEngine(prepared: true, active: false) // SDK pause snapshot.
      precondition(value.authenticated && !value.engineActive)
      precondition(!value.requestActivation())
      value.setForeground(true)
      activate(value)
    }
    test("initial zero-size waits for UIKit layout") {
      let value = make(size: .zero)
      value.authenticationSucceeded()
      precondition(!value.requestActivation())
      value.resize(CGRect(x: 0, y: 0, width: 1024, height: 768))
      activate(value)
      value.addViews()
      precondition(value.requestView())
    }
    test("addViewSucceeded reapplies current bounds; zero -> resize -> loaded") {
      let value = make()
      value.authenticationSucceeded()
      activate(value)
      value.addViews()
      precondition(value.requestView())
      value.addViewSucceeded(currentBounds: .zero)
      precondition(value.bounds == .zero && !value.markLoaded())
      let resized = CGRect(x: 0, y: 0, width: 600, height: 800)
      value.resize(resized)
      precondition(value.bounds == resized && value.markLoaded())
    }
    test("missing addView callback never claims loaded") {
      let value = make()
      value.authenticationSucceeded()
      activate(value)
      value.addViews()
      precondition(value.requestView())
      precondition(!value.markLoaded() && value.stage == .addViewsRequested)
    }
    test("addView failure is terminal and stage history is bounded") {
      let value = make()
      value.fail()
      precondition(value.terminalFailure && value.stage == .failed)
      for _ in 0..<30 { value.addViews() }
      precondition(value.stages.count == 24)
    }
    for result in [false, true] {
      test("prepare returns \(result); later auth success still activates/loads") {
        let value = make()
        value.prepareReturned(result)
        precondition(!value.failed && value.retryCount == 0)
        value.authenticationSucceeded()
        activate(value)
        finishView(value)
        precondition(value.prepareReturn == result && value.authCallback == .succeeded)
      }
    }
    test("false return; SDK prepared without auth callback can activate/load") {
      let value = make()
      value.prepareReturned(false)
      value.observeEngine(prepared: true, active: false)
      precondition(value.authCallback == .none && !value.failed)
      activate(value)
      finishView(value)
      precondition(value.loaded && value.retryCount == 0)
    }
    test("false return followed by actual 401 is authentication failure") {
      let value = make()
      value.prepareReturned(false)
      precondition(!value.failed)
      value.authenticationFailed(401)
      precondition(value.authErrorCode == 401 && value.authCallback == .failed)
      precondition(value.terminalFailure && value.retryCount == 0)
    }
    test("false with no callback/prepared progress waits until prepare timeout") {
      let value = make()
      value.prepareReturned(false)
      precondition(value.deadlineReached(elapsed: 17.9) == nil && !value.failed)
      precondition(value.deadlineReached(elapsed: 18) == .prepareTimeout)
      precondition(value.stage == .prepareTimedOut && value.authErrorCode == nil)
      precondition(value.retryCount == 1 && value.retryDelay == 0.5)
    }
    test("engine diagnostics are SDK snapshots, not activation assumptions") {
      let value = make()
      value.observeEngine(prepared: true, active: false)
      precondition(value.enginePrepared && !value.engineActive)
      precondition(value.requestActivation())
      precondition(!value.engineActive)
      value.observeEngine(prepared: true, active: true)
      precondition(value.engineActive && value.stage == .engineActivated)
    }
    test("callback/prepared progress without a view is rendering timeout") {
      let value = make()
      value.prepareReturned(false)
      value.observeEngine(prepared: true, active: false)
      value.observeEngine(prepared: false, active: false)
      precondition(value.deadlineReached(elapsed: 18) == .timeout)
      precondition(value.terminalFailure && value.retryCount == 0)
      let authenticated = make()
      authenticated.authenticationSucceeded()
      precondition(authenticated.deadlineReached(elapsed: 18) == .timeout)
    }
    test("499 and prepare timeout share a bounded recovery budget") {
      let value = make()
      value.authenticationFailed(499)
      value.prepareRequested()
      precondition(value.deadlineReached(elapsed: 18) == .prepareTimeout)
      precondition(value.retryCount == 2 && value.retryDelay == 1.5)
      value.prepareRequested()
      value.prepareReturned(false)
      precondition(value.retryCount == 2 && !value.failed)
      precondition(value.deadlineReached(elapsed: 18) == .prepareTimeout)
      precondition(value.terminalFailure && value.retryDelay == nil)
    }
    test("foreground deadline and opaque SDK text remain privacy safe") {
      let value = make(foreground: false)
      precondition(value.deadlineReached(elapsed: 18) == nil)
      let raw = "appKey=secret-token; user=private; location=37.5,127.0"
      let safe = value.sanitizedStateDescription(raw)
      precondition(safe.available && safe.summary == "preparing")
      precondition(!safe.summary.contains("secret") && !safe.summary.contains("37.5"))
      precondition(!value.sanitizedStateDescription("").available)
    }
    print("Kakao native lifecycle: \(passed) tests passed")
  }
}
