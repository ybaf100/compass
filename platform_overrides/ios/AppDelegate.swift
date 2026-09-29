import CoreLocation
import Flutter
import KakaoMapsSDK
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
    if let registrar = self.registrar(forPlugin: "CompassKakaoMapView") {
      registrar.register(KakaoMapViewFactory(messenger: controller.binaryMessenger),
        withId: "app.destination_compass/kakao_map")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// The SDK remains entirely inside the native platform view. The app key is
/// passed from Dart at construction and never stored in Info.plist or logs.
private final class KakaoMapViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    KakaoMapPlatformView(frame: frame, id: viewId,
      key: (args as? [String: Any])?["appKey"] as? String ?? "", messenger: messenger)
  }
}

private final class KakaoMapPlatformView: NSObject, FlutterPlatformView,
    KMControllerDelegate, KakaoMapEventDelegate {
  private let container: KMViewContainer
  private let channel: FlutterMethodChannel
  private var controller: KMController?
  private var map: KakaoMap?
  private var layer: LabelLayer?
  private var pois: [String: Poi] = [:]
  private var kinds: [String: String] = [:]
  private var markers: [[String: Any]] = []
  private var pendingCamera: [String: Any]?
  private var bottomPadding: CGFloat = 0
  private var disposed = false
  private var failed = false
  private var foregroundObserver: NSObjectProtocol?
  private var backgroundObserver: NSObjectProtocol?

  init(frame: CGRect, id: Int64, key: String, messenger: FlutterBinaryMessenger) {
    container = KMViewContainer(frame: frame)
    channel = FlutterMethodChannel(name: "app.destination_compass/kakao_map_\(id)",
                                   binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      failed = true
      event(["type": "failed"])
      return
    }
    SDKInitializer.InitSDK(appKey: key)
    controller = KMController(viewContainer: container)
    controller?.delegate = self
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.controller?.activateEngine()
    }
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.controller?.pauseEngine()
    }
    controller?.prepareEngine()
    controller?.activateEngine()
  }

  func view() -> UIView { container }

  deinit {
    disposed = true
    if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    channel.setMethodCallHandler(nil)
    controller?.pauseEngine()
    controller?.resetEngine()
  }

  private func event(_ payload: [String: Any]) {
    if !disposed { channel.invokeMethod("event", arguments: payload) }
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "status":
      result(map != nil ? "loaded" : failed ? "failed" : "initializing")
    case "overlays":
      markers = ((call.arguments as? [String: Any])?["markers"] as? [[String: Any]]) ?? []
      applyMarkers()
      result(nil)
    case "camera":
      pendingCamera = call.arguments as? [String: Any]
      if let pendingCamera { applyCamera(pendingCamera) }
      result(nil)
    case "padding":
      bottomPadding = CGFloat((call.arguments as? [String: Any])?["bottom"] as? Double ?? 0)
      map?.setMargins(UIEdgeInsets(top: 0, left: 0, bottom: bottomPadding, right: 0))
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  func authenticationFailed(_ errorCode: Int, desc: String) {
    failed = true
    event(["type": "failed"])
  }

  func addViews() {
    let info = MapviewInfo(viewName: "compassMap", viewInfoName: "map",
      defaultPosition: MapPoint(longitude: 126.979, latitude: 37.5666), defaultLevel: 14)
    controller?.addView(info)
  }

  func addViewSucceeded(_ viewName: String, viewInfoName: String) {
    guard let kakaoMap = controller?.getView(viewName) as? KakaoMap else {
      event(["type": "failed"])
      return
    }
    map = kakaoMap
    failed = false
    kakaoMap.eventDelegate = self
    kakaoMap.viewRect = container.bounds
    kakaoMap.keepLevelOnResize = true
    kakaoMap.setMargins(UIEdgeInsets(top: 0, left: 0,
      bottom: bottomPadding, right: 0))
    let manager = kakaoMap.getLabelManager()
    layer = manager.addLabelLayer(option: LabelLayerOptions(layerID: "compassOverlays",
      competitionType: .none, competitionUnit: .poi, orderType: .rank, zOrder: 10))
    layer?.setClickable(true)
    let palette: [String: UIColor] = [
      "user": .systemBlue, "candidate": .systemIndigo, "destination": .systemOrange,
      "member": .systemTeal, "stale": .systemGray, "ping": .systemYellow]
    for (kind, color) in palette {
      let icon = PoiIconStyle(symbol: iconImage(color),
        anchorPoint: CGPoint(x: 0.5, y: 0.5))
      let text = TextStyle(fontSize: 15, fontColor: .white,
        strokeThickness: 2, strokeColor: .black)
      let line = PoiTextLineStyle(textStyle: text, textLayout: .bottom)
      let style = PerLevelPoiStyle(iconStyle: icon,
        textStyle: PoiTextStyle(textLineStyles: [line]), level: 0)
      manager.addPoiStyle(PoiStyle(styleID: "compass-\(kind)", styles: [style]))
    }
    applyMarkers()
    if let pendingCamera { applyCamera(pendingCamera) }
    emitCamera()
    event(["type": "loaded"])
  }

  func addViewFailed(_ viewName: String, viewInfoName: String) {
    failed = true
    event(["type": "failed"])
  }

  func containerDidResized(_ size: CGSize) {
    map?.viewRect = CGRect(origin: .zero, size: size)
  }

  private func iconImage(_ color: UIColor) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36))
    return renderer.image { _ in
      UIColor.white.setFill()
      UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 34, height: 34)).fill()
      color.setFill()
      UIBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 28, height: 28)).fill()
    }
  }

  private func applyMarkers() {
    guard let layer else { return }
    let wanted = Set(markers.compactMap { $0["id"] as? String })
    for id in Array(pois.keys) where !wanted.contains(id) {
      layer.removePoi(poiID: id)
      pois.removeValue(forKey: id)
      kinds.removeValue(forKey: id)
    }
    for marker in markers {
      guard let id = marker["id"] as? String,
        let lat = marker["latitude"] as? Double,
        let lon = marker["longitude"] as? Double else { continue }
      let position = MapPoint(longitude: lon, latitude: lat)
      let kind = marker["kind"] as? String ?? "candidate"
      let styleID = "compass-\(kind)"
      let caption = marker["label"] as? String ?? ""
      if let poi = pois[id] {
        // Dart's MemberMarkerMotion supplies intermediate positions.
        poi.moveAt(position, duration: 0)
        if kinds[id] != kind || !caption.isEmpty {
          poi.changeTextAndStyle(texts: [PoiText(text: caption, styleIndex: 0)],
            styleID: styleID)
        }
      } else {
        let options = PoiOptions(styleID: styleID, poiID: id)
        options.clickable = id.hasPrefix("member:")
        options.addText(PoiText(text: caption, styleIndex: 0))
        let poi = layer.addPoi(option: options, at: position)
        poi?.show()
        if let poi { pois[id] = poi }
      }
      kinds[id] = kind
    }
  }

  private func applyCamera(_ camera: [String: Any]) {
    guard let map,
      let lat = camera["latitude"] as? Double,
      let lon = camera["longitude"] as? Double else { return }
    let zoom = max(map.minLevel, min(map.maxLevel, camera["zoom"] as? Int ?? 14))
    let bearing = (camera["bearing"] as? Double ?? 0) * .pi / 180
    let pitch = (camera["pitch"] as? Double ?? 0) * .pi / 180
    // Kakao iOS uses counter-clockwise rotation; the app uses clockwise.
    map.moveCamera(CameraUpdate.make(target: MapPoint(longitude: lon, latitude: lat),
      zoomLevel: zoom, rotation: -bearing, tilt: pitch, mapView: map))
  }

  private func emitCamera() {
    guard let map else { return }
    let center = map.getPosition(CGPoint(x: 0.5, y: 0.5)).wgsCoord
    event(["type": "camera", "latitude": center.latitude,
      "longitude": center.longitude, "zoom": map.zoomLevel,
      "bearing": -map.rotationAngle * 180 / .pi,
      "pitch": map.tiltAngle * 180 / .pi])
  }

  func terrainDidTapped(kakaoMap: KakaoMap, position: MapPoint) {
    let point = position.wgsCoord
    event(["type": "tap", "latitude": point.latitude, "longitude": point.longitude])
  }

  func terrainDidLongPressed(kakaoMap: KakaoMap, position: MapPoint) {
    terrainDidTapped(kakaoMap: kakaoMap, position: position)
  }

  func poiDidTapped(kakaoMap: KakaoMap, layerID: String,
                    poiID: String, position: MapPoint) {
    if poiID.hasPrefix("member:") {
      event(["type": "memberTap", "id": String(poiID.dropFirst("member:".count))])
    }
  }

  func cameraWillMove(kakaoMap: KakaoMap, by: MoveBy) {
    if by != .notUserAction { event(["type": "gesture"]) }
  }

  func cameraDidStopped(kakaoMap: KakaoMap, by: MoveBy) { emitCamera() }
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
