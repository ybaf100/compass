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
  private var userHeading: Double?
  private var userHasOrientation = false
  private var cameraHeadingLink: CADisplayLink?
  private lazy var cameraHeadingTarget = KakaoHeadingFrameTarget(owner: self)
  private var cameraMoving = false
  private var markers: [[String: Any]] = []
  private var pendingCamera: [String: Any]?
  private var bottomPadding: CGFloat = 0
  private var disposed = false
  private var failureCategory = "initialization"
  private var authRetry: DispatchWorkItem?
  private var engineWatch: [DispatchWorkItem] = []
  private var stateDescriptionAvailable: Bool?
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
      self.watchEngineIfNeeded()
      self.updateUserHeading(animated: false)
    }
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self else { return }
      self.lifecycle.setForeground(false)
      self.authRetry?.cancel()
      self.authRetry = nil
      self.cancelEngineWatch()
      self.stopCameraHeadingWatch()
      self.controller?.pauseEngine()
      self.observeEngineState()
    }
    prepareEngine()
  }

  func view() -> UIView { host }

  deinit {
    disposed = true
    authRetry?.cancel()
    cancelEngineWatch()
    stopCameraHeadingWatch()
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
     "prepareReturn": lifecycle.prepareReturn.map { $0 as Any } ?? NSNull(),
     "enginePrepared": controller.map { $0.isEnginePrepared as Any } ?? NSNull(),
     "engineActive": controller.map { $0.isEngineActive as Any } ?? NSNull(),
     "authCallback": lifecycle.authCallback.rawValue,
     "engineStateSummary": lifecycle.engineStateSummary,
     "stateDescriptionAvailable": stateDescriptionAvailable.map { $0 as Any } ?? NSNull(),
     "nativeTimeoutManaged": true,
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
    guard !disposed, let controller else { return }
    cancelEngineWatch()
    lifecycle.prepareRequested()
    // The official API does not define false as fatal. Delegates and SDK state
    // are authoritative; keep the raw return for diagnostics only.
    lifecycle.prepareReturned(controller.prepareEngine())
    activateIfAllowed()
    emitDiagnostics()
    watchEngineIfNeeded()
  }

  private func observeEngineState() {
    guard let controller else { return }
    lifecycle.observeEngine(prepared: controller.isEnginePrepared,
      active: controller.isEngineActive)
    #if DEBUG
    // Opaque SDK text may contain sensitive data. Never store, forward or log
    // it. Only a fixed summary and presence boolean survive sanitization.
    let safe = lifecycle.sanitizedStateDescription(controller.getStateDescMessage())
    stateDescriptionAvailable = safe.available
    #endif
  }

  private func cancelEngineWatch() {
    engineWatch.forEach { $0.cancel() }
    engineWatch.removeAll()
  }

  private func watchEngineIfNeeded() {
    guard !disposed, lifecycle.foreground, !lifecycle.loaded,
      !lifecycle.failed, engineWatch.isEmpty else { return }
    // Bounded state snapshots, not indefinite polling. Handles prepared state
    // without an auth callback, as permitted by the official drawing samples.
    let delays: [TimeInterval] = [0.5, 1.5, 3, 6, 12, KakaoEngineLifecycle.timeoutSeconds]
    for delay in delays {
      let work = DispatchWorkItem { [weak self] in
        guard let self, !self.disposed, self.lifecycle.foreground else { return }
        self.activateIfAllowed()
        self.emitDiagnostics()
        if let reason = self.lifecycle.deadlineReached(elapsed: delay) {
          self.failureCategory = reason.rawValue
          self.cancelEngineWatch()
          if self.lifecycle.terminalFailure { self.emitFailure() }
          else { self.scheduleAuthRetry() }
        }
      }
      engineWatch.append(work)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
  }

  private func activateIfAllowed() {
    guard !disposed else { return }
    observeEngineState()
    if lifecycle.requestActivation() {
      controller?.activateEngine()
      observeEngineState()
    }
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
      cancelEngineWatch()
      var payload = diagnostics()
      payload["type"] = "loaded"
      event(payload)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "status":
      activateIfAllowed()
      var status = diagnostics()
      status["type"] = lifecycle.terminalFailure ? "failed" : lifecycle.loaded ? "loaded" : "initializing"
      status["category"] = failureCategory
      result(status)
    case "overlays":
      markers = ((call.arguments as? [String: Any])?["markers"] as? [[String: Any]]) ?? []
      applyMarkers()
      result(nil)
    case "userHeading":
      let value = (call.arguments as? [String: Any])?["heading"] as? Double
      userHeading = value?.isFinite == true ? value : nil
      updateUserHeading(animated: true)
      if cameraMoving { startCameraHeadingWatch() }
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
    cancelEngineWatch()
    // Do not forward/log desc: it can contain credentials or request details.
    map = nil
    layer = nil
    pois.removeAll()
    kinds.removeAll()
    lifecycle.authenticationFailed(errorCode)
    observeEngineState()
    #if DEBUG
    print("[passcom] kakao.authErrorCode: \(errorCode)")
    #endif
    if lifecycle.terminalFailure { emitFailure() }
    else { scheduleAuthRetry() }
  }

  func addViews() {
    guard !disposed, !lifecycle.failed else { return }
    observeEngineState()
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
    guard !disposed, !lifecycle.failed else { return }
    guard let kakaoMap = controller?.getView(viewName) as? KakaoMap else {
      failureCategory = "addView"
      cancelEngineWatch()
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
      "user": .systemBlue, "userHeading": .systemBlue,
      "candidate": .systemIndigo, "destination": .systemOrange,
      "member": .systemTeal, "stale": .systemGray, "ping": .systemYellow]
    for (kind, color) in palette {
      let icon = PoiIconStyle(symbol: iconImage(color, kind: kind),
        anchorPoint: CGPoint(x: 0.5, y: 0.5))
      let text = TextStyle(fontSize: 12, fontColor: .white,
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
    observeEngineState()
    announceLoadedIfAllowed()
  }

  func addViewFailed(_ viewName: String, viewInfoName: String) {
    guard !disposed else { return }
    failureCategory = "addView"
    cancelEngineWatch()
    lifecycle.fail()
    emitFailure()
  }

  func containerDidResized(_ size: CGSize) {
    updateLayout()
  }

  private func iconImage(_ color: UIColor, kind: String) -> UIImage {
    let side = CGFloat(KakaoMarkerGeometry.canvas(kind))
    let diameter = CGFloat(KakaoMarkerGeometry.diameter(kind))
    let center = side / 2
    // SDK scales logical icon assets for its display. Avoid a second Retina
    // multiplication; transparent member padding keeps a forgiving tap area.
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    return renderer.image { _ in
      if kind == "userHeading" {
        let cone = UIBezierPath()
        cone.move(to: CGPoint(x: center, y: center))
        cone.addLine(to: CGPoint(x: center - 12, y: 4))
        cone.addQuadCurve(to: CGPoint(x: center + 12, y: 4),
          controlPoint: CGPoint(x: center, y: -2))
        cone.close()
        color.withAlphaComponent(0.22).setFill()
        cone.fill()
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: center, y: 3))
        arrow.addLine(to: CGPoint(x: center + 5, y: 11))
        arrow.addLine(to: CGPoint(x: center, y: 9))
        arrow.addLine(to: CGPoint(x: center - 5, y: 11))
        arrow.close()
        color.setFill()
        arrow.fill()
      }
      UIColor.white.setFill()
      UIBezierPath(ovalIn: CGRect(x: center - diameter/2, y: center - diameter/2,
        width: diameter, height: diameter)).fill()
      color.setFill()
      UIBezierPath(ovalIn: CGRect(x: center - diameter/2 + 2, y: center - diameter/2 + 2,
        width: diameter - 4, height: diameter - 4)).fill()
    }
  }

  private func applyMarkers() {
    guard let layer else { return }
    let previousHeading = userHeading
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
      if id == "user", marker.keys.contains("heading") {
        let value = marker["heading"] as? Double
        userHeading = value?.isFinite == true ? value : nil
      }
      let displayKind = id == "user" && userHeading != nil ? "userHeading" : kind
      let styleID = "compass-\(displayKind)"
      let caption = id == "user" ? "" : marker["label"] as? String ?? ""
      if let poi = pois[id] {
        // Dart's MemberMarkerMotion supplies intermediate positions.
        poi.moveAt(position, duration: 0)
        if kinds[id] != displayKind || !caption.isEmpty {
          poi.changeTextAndStyle(texts: [PoiText(text: caption, styleIndex: 0)],
            styleID: styleID)
        }
      } else {
        let options = PoiOptions(styleID: styleID, poiID: id)
        options.clickable = id.hasPrefix("member:")
        if id == "user" {
          // Billboard basis: rotation below is already camera-compensated.
          options.transformType = .default
          userHasOrientation = false
        }
        options.addText(PoiText(text: caption, styleIndex: 0))
        let poi = layer.addPoi(option: options, at: position)
        poi?.show()
        if let poi { pois[id] = poi }
      }
      kinds[id] = displayKind
    }
    // Friend motion frames must not cancel the user's in-flight rotation.
    if userHeading != previousHeading || !userHasOrientation {
      updateUserHeading(animated: true)
    }
  }

  private func updateUserHeading(animated: Bool) {
    guard let map, let poi = pois["user"] else { return }
    let kind = userHeading == nil ? "user" : "userHeading"
    if kinds["user"] != kind {
      poi.changeTextAndStyle(texts: [], styleID: "compass-\(kind)")
      kinds["user"] = kind
    }
    guard let heading = userHeading else {
      poi.rotateAt(0, duration: 0)
      userHasOrientation = false
      stopCameraHeadingWatch()
      return
    }
    let bearing = -map.rotationAngle * 180 / .pi
    let display = KakaoMarkerGeometry.display(heading: heading, cameraBearing: bearing)
    // Default supplies a screen-up billboard basis. Apply the compensated
    // offset once; Kakao iOS uses counter-clockwise radians.
    let current = -poi.orientation * 180 / .pi
    let target = KakaoMarkerGeometry.target(from: current, to: display)
    if userHasOrientation && abs(target - current) < 0.15 { return }
    poi.rotateAt(-target * .pi / 180, duration: animated && userHasOrientation ? 90 : 0)
    userHasOrientation = true
  }

  private func startCameraHeadingWatch() {
    guard cameraHeadingLink == nil, userHeading != nil, !disposed, lifecycle.foreground else { return }
    let link = CADisplayLink(target: cameraHeadingTarget, selector: #selector(KakaoHeadingFrameTarget.tick))
    cameraHeadingLink = link
    link.add(to: .main, forMode: .common)
  }

  private func stopCameraHeadingWatch() {
    cameraHeadingLink?.invalidate()
    cameraHeadingLink = nil
  }

  fileprivate func cameraHeadingFrame() {
    guard cameraMoving, map != nil, !disposed, lifecycle.foreground else {
      stopCameraHeadingWatch()
      return
    }
    updateUserHeading(animated: false)
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
    cameraMoving = true
    startCameraHeadingWatch()
    if by != .notUserAction { event(["type": "gesture"]) }
  }

  func cameraDidStopped(kakaoMap: KakaoMap, by: MoveBy) {
    cameraMoving = false
    stopCameraHeadingWatch()
    updateUserHeading(animated: false)
    emitCamera()
  }
}

/// Weak display-link target: a native view cannot be retained by its frame loop.
private final class KakaoHeadingFrameTarget: NSObject {
  weak var owner: KakaoMapPlatformView?
  init(owner: KakaoMapPlatformView) { self.owner = owner }
  @objc func tick() { owner?.cameraHeadingFrame() }
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
