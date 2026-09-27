import CoreLocation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let headingBridge = HeadingBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    let events = FlutterEventChannel(
      name: "app.destination_compass/heading",
      binaryMessenger: controller.binaryMessenger)
    events.setStreamHandler(headingBridge)
    let methods = FlutterMethodChannel(
      name: "app.destination_compass/heading_control",
      binaryMessenger: controller.binaryMessenger)
    methods.setMethodCallHandler { [weak self] call, result in
      self?.headingBridge.handle(call, result: result)
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class HeadingBridge: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError? {
    sink = events
    guard CLLocationManager.headingAvailable() else {
      events(NSNull())
      return nil
    }
    manager.delegate = self
    manager.headingFilter = 1
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(self,
      selector: #selector(updateOrientation),
      name: UIDevice.orientationDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self,
      selector: #selector(resume),
      name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self,
      selector: #selector(pause),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    updateOrientation()
    manager.startUpdatingHeading()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager.stopUpdatingHeading()
    NotificationCenter.default.removeObserver(self)
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
    sink = nil
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    if call.method == "updateLocation" { result(nil) }
    else { result(FlutterMethodNotImplemented) }
  }

  @objc private func resume() {
    if sink != nil { manager.startUpdatingHeading() }
  }

  @objc private func pause() { manager.stopUpdatingHeading() }

  @objc private func updateOrientation() {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    switch scene?.interfaceOrientation {
    case .landscapeLeft: manager.headingOrientation = .landscapeLeft
    case .landscapeRight: manager.headingOrientation = .landscapeRight
    case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
    default: manager.headingOrientation = .portrait
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
    guard heading.headingAccuracy >= 0 else {
      sink?(NSNull())
      return
    }
    let trueNorth = heading.trueHeading >= 0
    sink?([
      "heading": trueNorth ? heading.trueHeading : heading.magneticHeading,
      "trueNorth": trueNorth,
      "accuracy": heading.headingAccuracy
    ])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    sink?(NSNull())
  }
}
