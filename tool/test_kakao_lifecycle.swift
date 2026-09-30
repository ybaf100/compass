import Foundation

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

  static func main() {
    test("auth success -> activate -> addViews -> loaded") {
      let value = make()
      precondition(!value.requestActivation())
      value.authenticationSucceeded()
      precondition(value.requestActivation())
      precondition(!value.requestActivation(), "Do not activate twice")
      value.addViews()
      precondition(value.requestView())
      precondition(!value.requestView(), "Stable single view")
      value.addViewSucceeded(currentBounds: value.bounds)
      precondition(value.markLoaded())
      precondition(!value.markLoaded(), "Single loaded callback")
      precondition(value.stages == [.platformViewCreated, .sdkInitialized,
        .enginePrepared, .authenticating, .authenticated, .engineActivated,
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
      precondition(value.requestActivation())
    }
    test("pause preserves authentication without activating in background") {
      let value = make()
      value.authenticationSucceeded()
      precondition(value.requestActivation())
      value.setForeground(false)
      precondition(value.authenticated && !value.engineActive)
      precondition(!value.requestActivation())
      value.setForeground(true)
      precondition(value.requestActivation())
    }
    test("initial zero-size waits for UIKit layout") {
      let value = make(size: .zero)
      value.authenticationSucceeded()
      precondition(!value.requestActivation())
      value.resize(CGRect(x: 0, y: 0, width: 1024, height: 768))
      precondition(value.requestActivation())
      value.addViews()
      precondition(value.requestView())
    }
    test("addViewSucceeded reapplies current bounds; zero -> resize -> loaded") {
      let value = make()
      value.authenticationSucceeded()
      precondition(value.requestActivation())
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
      precondition(value.requestActivation())
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
    print("Kakao native lifecycle: \(passed) tests passed")
  }
}
