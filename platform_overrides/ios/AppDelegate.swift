import CoreLocation
import Flutter
import KakaoMapsSDK
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let headingBridge = HeadingBridge()

  // UIScene creates the implicit engine after application launch. Register all
  // plugins and custom channels here, without depending on an AppDelegate window.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.applicationRegistrar
    let messenger = registrar.messenger()
    let events = FlutterEventChannel(
      name: "app.destination_compass/heading",
      binaryMessenger: messenger)
    events.setStreamHandler(headingBridge)
    let methods = FlutterMethodChannel(
      name: "app.destination_compass/heading_control",
      binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in
      self?.headingBridge.handle(call, result: result)
    }
    let runtime = FlutterMethodChannel(name: "app.destination_compass/runtime",
      binaryMessenger: messenger)
    runtime.setMethodCallHandler { call, result in
      if call.method == "bundleIdentifier" { result(Bundle.main.bundleIdentifier) }
      else { result(FlutterMethodNotImplemented) }
    }
    registrar.register(KakaoMapViewFactory(messenger: messenger),
      withId: "app.destination_compass/kakao_map")
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

/// Flutter may create a 0x0 view. Observe UIKit layout independently of the SDK
/// so engine activation is not required to discover the first nonzero bounds.
private final class KakaoMapHostView: UIView {
  let mapContainer: KMViewContainer
  var onLayout: (() -> Void)?

  override init(frame: CGRect) {
    mapContainer = KMViewContainer(frame: CGRect(origin: .zero, size: frame.size))
    super.init(frame: frame)
    addSubview(mapContainer)
  }

  required init?(coder: NSCoder) { fatalError("Programmatic platform view only") }

  override func layoutSubviews() {
    super.layoutSubviews()
    mapContainer.frame = bounds
    onLayout?()
  }
}

private final class KakaoMapPlatformView: NSObject, FlutterPlatformView,
    MapControllerDelegate, KakaoMapEventDelegate {
  private let host: KakaoMapHostView
  private let container: KMViewContainer
  private let lifecycle: KakaoEngineLifecycle
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
  private var failureCategory = "initialization"
  private var authRetry: DispatchWorkItem?
  private var foregroundObserver: NSObjectProtocol?
  private var backgroundObserver: NSObjectProtocol?

  init(frame: CGRect, id: Int64, key: String, messenger: FlutterBinaryMessenger) {
    let mapHost = KakaoMapHostView(frame: frame)
    host = mapHost
    container = mapHost.mapContainer
    lifecycle = KakaoEngineLifecycle(
      keyPresent: !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      foreground: UIApplication.shared.applicationState == .active,
      bounds: mapHost.mapContainer.bounds)
    channel = FlutterMethodChannel(name: "app.destination_compass/kakao_map_\(id)",
                                   binaryMessenger: messenger)
    super.init()
    lifecycle.onStage = { [weak self] stage in
      #if DEBUG
      print("[passcom] kakao.stage: \(stage.rawValue)")
      #endif
      self?.emitDiagnostics()
    }
    host.onLayout = { [weak self] in self?.updateLayout() }
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    emitDiagnostics()
    guard lifecycle.keyPresent else {
      lifecycle.fail()
      emitFailure()
      return
    }
    SDKInitializer.InitSDK(appKey: key)
    lifecycle.sdkDidInitialize()
    controller = KMController(viewContainer: container)
    guard controller != nil else {
      lifecycle.fail()
      emitFailure()
      return
    }
    controller?.delegate = self
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self, !self.disposed else { return }
      self.lifecycle.setForeground(true)
      self.scheduleAuthRetry()
      self.activateIfAllowed()
    }
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self else { return }
      self.lifecycle.setForeground(false)
      self.authRetry?.cancel()
      self.authRetry = nil
      self.controller?.pauseEngine()
    }
    prepareEngine()
  }

  func view() -> UIView { host }

  deinit {
    disposed = true
    authRetry?.cancel()
    host.onLayout = nil
    lifecycle.onStage = nil
    if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    channel.setMethodCallHandler(nil)
    controller?.pauseEngine()
    controller?.resetEngine()
  }

  private func event(_ payload: [String: Any]) {
    if !disposed { channel.invokeMethod("event", arguments: payload) }
  }

  private func diagnostics() -> [String: Any] {
    ["stage": lifecycle.stage.rawValue,
     "stages": lifecycle.stages.map { $0.rawValue },
     "keyPresent": lifecycle.keyPresent,
     "sdkInitialized": lifecycle.sdkInitialized,
     "runtimeBundleId": (Bundle.main.bundleIdentifier as Any?) ?? NSNull(),
     "authErrorCode": lifecycle.authErrorCode.map { $0 as Any } ?? NSNull(),
     "retryCount": lifecycle.retryCount,
     "retryPending": lifecycle.retryDelay != nil,
     "containerWidth": Double(lifecycle.bounds.size.width),
     "containerHeight": Double(lifecycle.bounds.size.height)]
  }

  private func emitDiagnostics() {
    var payload = diagnostics()
    payload["type"] = "diagnostics"
    event(payload)
  }

  private func emitFailure() {
    var payload = diagnostics()
    payload["type"] = "failed"
    payload["category"] = failureCategory
    event(payload)
  }

  private func prepareEngine() {
    guard !disposed else { return }
    lifecycle.prepareRequested()
    if controller?.prepareEngine() == false {
      failureCategory = "initialization"
      lifecycle.fail()
      emitFailure()
    }
  }

  private func activateIfAllowed() {
    guard !disposed else { return }
    if lifecycle.requestActivation() { controller?.activateEngine() }
    addViewIfAllowed()
    announceLoadedIfAllowed()
  }

  private func scheduleAuthRetry() {
    guard !disposed, lifecycle.foreground,
      let delay = lifecycle.retryDelay, authRetry == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.disposed else { return }
      self.authRetry = nil
      guard self.lifecycle.foreground, self.lifecycle.retryDelay != nil else { return }
      self.prepareEngine()
    }
    authRetry = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func updateLayout() {
    guard !disposed else { return }
    lifecycle.resize(container.bounds)
    map?.viewRect = container.bounds
    activateIfAllowed()
    emitDiagnostics()
  }

  private func announceLoadedIfAllowed() {
    if lifecycle.markLoaded() {
      var payload = diagnostics()
      payload["type"] = "loaded"
      event(payload)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "status":
      var status = diagnostics()
      status["type"] = lifecycle.terminalFailure ? "failed" : lifecycle.loaded ? "loaded" : "initializing"
      status["category"] = failureCategory
      result(status)
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

  func authenticationSucceeded() {
    guard !disposed else { return }
    authRetry?.cancel()
    authRetry = nil
    lifecycle.authenticationSucceeded()
    activateIfAllowed()
  }

  func authenticationFailed(_ errorCode: Int, desc: String) {
    guard !disposed else { return }
    authRetry?.cancel()
    authRetry = nil
    failureCategory = "authentication"
    // Do not forward/log desc: it can contain credentials or request details.
    map = nil
    layer = nil
    pois.removeAll()
    kinds.removeAll()
    lifecycle.authenticationFailed(errorCode)
    #if DEBUG
    print("[passcom] kakao.authErrorCode: \(errorCode)")
    #endif
    if lifecycle.terminalFailure { emitFailure() }
    else { scheduleAuthRetry() }
  }

  func addViews() {
    guard !disposed else { return }
    lifecycle.addViews()
    addViewIfAllowed()
  }

  private func addViewIfAllowed() {
    guard lifecycle.requestView() else { return }
    let info = MapviewInfo(viewName: "compassMap", viewInfoName: "map",
      defaultPosition: MapPoint(longitude: 126.979, latitude: 37.5666), defaultLevel: 14)
    controller?.addView(info)
  }

  func addViewSucceeded(_ viewName: String, viewInfoName: String) {
    guard !disposed else { return }
    guard let kakaoMap = controller?.getView(viewName) as? KakaoMap else {
      failureCategory = "addView"
      lifecycle.fail()
      emitFailure()
      return
    }
    map = kakaoMap
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
      let line = PoiTextLineStyle(textStyle: text)
      let style = PerLevelPoiStyle(iconStyle: icon,
        textStyle: PoiTextStyle(textLineStyles: [line]), level: 0)
      manager.addPoiStyle(PoiStyle(styleID: "compass-\(kind)", styles: [style]))
    }
    applyMarkers()
    if let pendingCamera { applyCamera(pendingCamera) }
    emitCamera()
    lifecycle.addViewSucceeded(currentBounds: container.bounds)
    announceLoadedIfAllowed()
  }

  func addViewFailed(_ viewName: String, viewInfoName: String) {
    guard !disposed else { return }
    failureCategory = "addView"
    lifecycle.fail()
    emitFailure()
  }

  func containerDidResized(_ size: CGSize) {
    updateLayout()
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
