package com.ybaf100.compass

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import android.view.Choreographer
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.KakaoMapSdk
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.MapView
import com.kakao.vectormap.GestureType
import com.kakao.vectormap.camera.CameraPosition
import com.kakao.vectormap.camera.CameraUpdateFactory
import com.kakao.vectormap.label.Label
import com.kakao.vectormap.label.LabelOptions
import com.kakao.vectormap.label.LabelStyles
import com.kakao.vectormap.label.LabelStyle
import com.kakao.vectormap.label.LabelTextBuilder
import com.kakao.vectormap.label.TransformMethod
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.PI

internal class KakaoMapViewFactory(
    private val context: Context, private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val views = mutableSetOf<KakaoMapPlatformView>()

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val key = (args as? Map<*, *>)?.get("appKey") as? String ?: ""
        return KakaoMapPlatformView(context, messenger, viewId, key) { views.remove(it) }
            .also { views.add(it) }
    }

    fun pause() = views.toList().forEach { it.pause() }
    fun resume() = views.toList().forEach { it.resume() }
    fun dispose() = views.toList().forEach { it.dispose() }
}

internal class KakaoMapPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    id: Int,
    appKey: String,
    private val onDisposed: (KakaoMapPlatformView) -> Unit
) : PlatformView {
    private val mapView = MapView(context)
    private val channel = MethodChannel(messenger, "app.destination_compass/kakao_map_$id")
    private var map: KakaoMap? = null
    private val labels = mutableMapOf<String, Label>()
    private val kinds = mutableMapOf<String, String>()
    private val styles = mutableMapOf<String, LabelStyles>()
    private var markerScale = 1.25
    private val installedMarkerScales = mutableSetOf<Int>()
    private var pendingMarkers: List<Map<*, *>> = emptyList()
    private var pendingCamera: Map<*, *>? = null
    private var bottomPadding = 0.0
    private var disposed = false
    private var failed = false
    private val keyPresent = appKey.isNotBlank()
    private var sdkInitialized = false
    private var userHeading: Double? = null
    private var userHasOrientation = false
    private var cameraMoving = false
    private var watchingCameraHeading = false
    private val cameraHeadingFrame = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (disposed || !cameraMoving || map == null) { stopCameraHeadingWatch(); return }
            updateUserHeading(false)
            if (watchingCameraHeading) Choreographer.getInstance().postFrameCallback(this)
        }
    }

    init {
        channel.setMethodCallHandler(::handle)
        if (appKey.isBlank()) {
            failed = true
            event(mapOf("type" to "failed"))
        } else {
            try {
                KakaoMapSdk.init(context.applicationContext, appKey)
                sdkInitialized = true
                mapView.start(object : MapLifeCycleCallback() {
                    override fun onMapDestroy() { map = null }
                    override fun onMapError(error: Exception) {
                        failed = true
                        event(mapOf("type" to "failed"))
                    }
                }, object : KakaoMapReadyCallback() {
                    override fun onMapReady(kakaoMap: KakaoMap) {
                        if (disposed) return
                        map = kakaoMap
                        failed = false
                        kakaoMap.setOnMapClickListener { _, position, _, _ ->
                            event(mapOf("type" to "tap", "latitude" to position.latitude,
                                "longitude" to position.longitude))
                        }
                        kakaoMap.setOnLabelClickListener { _, _, label ->
                            val labelId = label.labelId
                            if (labelId.startsWith("member:")) {
                                event(mapOf("type" to "memberTap", "id" to labelId.removePrefix("member:")))
                            }
                            true
                        }
                        kakaoMap.setOnCameraMoveStartListener { _, gesture ->
                            cameraMoving = true
                            startCameraHeadingWatch()
                            if (gesture != GestureType.Unknown) event(mapOf("type" to "gesture"))
                        }
                        kakaoMap.setOnCameraMoveEndListener { _, position, _ ->
                            cameraMoving = false
                            stopCameraHeadingWatch()
                            updateUserHeading(false)
                            cameraEvent(position)
                        }
                        installStyles(kakaoMap)
                        applyPadding()
                        applyMarkers()
                        pendingCamera?.let { applyCamera(it) }
                        cameraEvent(kakaoMap.cameraPosition)
                        event(mapOf("type" to "loaded"))
                    }
                })
            } catch (_: Exception) {
                failed = true
                event(mapOf("type" to "failed"))
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) { result.success(null); return }
        try {
            when (call.method) {
                "status" -> {
                    result.success(mapOf("type" to (if (failed) "failed" else if (map != null) "loaded" else "initializing"),
                        "category" to "initialization", "keyPresent" to keyPresent,
                        "sdkInitialized" to sdkInitialized,
                        "stage" to (if (failed) "failed" else if (map != null) "loaded" else "sdkInitialized")))
                    return
                }
                "overlays" -> {
                    pendingMarkers = (call.argument<List<*>>("markers") ?: emptyList<Any>())
                        .mapNotNull { it as? Map<*, *> }
                    applyMarkers()
                }
                "userHeading" -> {
                    userHeading = call.argument<Number>("heading")?.toDouble()?.takeIf { it.isFinite() }
                    updateUserHeading(true)
                    if (cameraMoving) startCameraHeadingWatch()
                }
                "markerScale" -> {
                    val next = KakaoMarkerGeometry.scale(call.argument<Number>("scale")?.toDouble() ?: 1.25)
                    if (markerScale != next) {
                        markerScale = next
                        map?.let { installStyles(it) }
                        for ((id, label) in labels) {
                            kinds[id]?.let { kind -> markerStyle(kind)?.let { label.setStyles(it); label.invalidate() } }
                        }
                    }
                }
                "camera" -> {
                    pendingCamera = call.arguments as? Map<*, *>
                    pendingCamera?.let { applyCamera(it) }
                }
                "padding" -> {
                    bottomPadding = (call.argument<Number>("bottom")?.toDouble() ?: 0.0)
                    applyPadding()
                }
                else -> { result.notImplemented(); return }
            }
            result.success(null)
        } catch (_: Exception) {
            result.error("MAP_OPERATION_FAILED", "Kakao map operation failed", null)
        }
    }

    private fun installStyles(kakaoMap: KakaoMap) {
        val scaleKey = (markerScale * 100).toInt()
        if (scaleKey in installedMarkerScales) return
        val palette = mapOf("user" to 0xFF328DFF.toInt(), "userHeading" to 0xFF328DFF.toInt(),
            "candidate" to 0xFF3970DF.toInt(), "destination" to 0xFFED6541.toInt(),
            "member" to 0xFF2EBF9F.toInt(), "stale" to 0xFF8796A0.toInt(),
            "ping" to 0xFFF0AF40.toInt())
        val manager = kakaoMap.labelManager ?: return
        for ((kind, color) in palette) {
            val density = context.resources.displayMetrics.density
            // Bitmap is already rendered at device density. Applying the SDK's
            // default dpScale again would make icons much too large.
            val style = LabelStyles.from(LabelStyle.from(icon(color, kind))
                .setApplyDpScale(false).setAnchorPoint(0.5f, 0.5f)
                .setTextStyles((12 * density * markerScale).toInt(), Color.WHITE,
                    (2 * density * markerScale).toInt().coerceAtLeast(1), Color.BLACK))
            manager.addLabelStyles(style)?.let { styles["$kind-$scaleKey"] = it }
        }
        installedMarkerScales.add(scaleKey) // At most 31 scale presets per native view.
    }

    private fun markerStyle(kind: String) = styles["$kind-${(markerScale * 100).toInt()}"]

    private fun icon(color: Int, kind: String): Bitmap {
        val density = context.resources.displayMetrics.density
        val side = KakaoMarkerGeometry.canvas(kind, markerScale).toFloat()
        val size = kotlin.math.ceil(side * density).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        bitmap.density = Bitmap.DENSITY_NONE
        val canvas = Canvas(bitmap)
        canvas.scale(density, density)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val center = side / 2
        canvas.translate(center, center)
        canvas.scale(markerScale.toFloat(), markerScale.toFloat())
        if (kind == "userHeading") {
            val cone = Path().apply {
                moveTo(0f, 0f); lineTo(-12f, -16f)
                quadTo(0f, -22f, 12f, -16f); close()
            }
            paint.color = color; paint.alpha = 56
            canvas.drawPath(cone, paint)
            paint.alpha = 255
            val arrow = Path().apply {
                moveTo(0f, -17f); lineTo(5f, -9f)
                lineTo(0f, -11f); lineTo(-5f, -9f); close()
            }
            canvas.drawPath(arrow, paint)
        }
        val diameter = KakaoMarkerGeometry.diameter(kind).toFloat()
        paint.color = Color.WHITE
        canvas.drawCircle(0f, 0f, diameter / 2, paint)
        paint.color = color
        canvas.drawCircle(0f, 0f, diameter / 2 - 2, paint)
        return bitmap
    }

    private fun applyMarkers() {
        val kakaoMap = map ?: return
        val layer = kakaoMap.labelManager?.layer ?: return
        val previousHeading = userHeading
        val desired = pendingMarkers.mapNotNull { it["id"] as? String }.toSet()
        for (id in labels.keys.toList()) {
            if (id !in desired) { labels.remove(id)?.remove(); kinds.remove(id) }
        }
        for (marker in pendingMarkers) {
            val id = marker["id"] as? String ?: continue
            val latitude = (marker["latitude"] as? Number)?.toDouble() ?: continue
            val longitude = (marker["longitude"] as? Number)?.toDouble() ?: continue
            val position = LatLng.from(latitude, longitude)
            val kind = marker["kind"] as? String ?: "candidate"
            if (id == "user" && marker.containsKey("heading")) {
                userHeading = (marker["heading"] as? Number)?.toDouble()?.takeIf { it.isFinite() }
            }
            val displayKind = if (id == "user" && userHeading != null) "userHeading" else kind
            val style = markerStyle(displayKind) ?: continue
            val caption = if (id == "user") "" else marker["label"] as? String ?: ""
            val existing = labels[id]
            if (existing == null) {
                labels[id] = layer.addLabel(LabelOptions.from(id, position)
                    .setStyles(style).setTexts(LabelTextBuilder().setTexts(caption))
                    .setTransform(if (id == "user") TransformMethod.AbsoluteRotation else TransformMethod.Default)
                    .setClickable(id.startsWith("member:")))
                if (id == "user") userHasOrientation = false
            } else {
                if (existing.position != position) {
                    // Dart's MemberMarkerMotion already interpolates short moves.
                    existing.moveTo(position)
                }
                if (kinds[id] != displayKind) existing.setStyles(style)
                existing.setTexts(LabelTextBuilder().setTexts(caption))
                existing.invalidate()
            }
            kinds[id] = displayKind
        }
        // Friend motion frames must not cancel the user's in-flight rotation.
        if (userHeading != previousHeading || !userHasOrientation) updateUserHeading(true)
    }

    private fun updateUserHeading(animated: Boolean) {
        val kakaoMap = map ?: return
        val label = labels["user"] ?: return
        val kind = if (userHeading == null) "user" else "userHeading"
        if (kinds["user"] != kind) {
            markerStyle(kind)?.let { label.setStyles(it); label.invalidate() }
            kinds["user"] = kind
        }
        val heading = userHeading
        if (heading == null) {
            label.rotateTo(0f); userHasOrientation = false
            stopCameraHeadingWatch(); return
        }
        val camera = kakaoMap.cameraPosition ?: return
        val bearing = camera.rotationAngle * 180 / PI
        val display = KakaoMarkerGeometry.display(heading, bearing)
        val current = label.rotation * 180 / PI
        val target = KakaoMarkerGeometry.target(current, display)
        if (userHasOrientation && kotlin.math.abs(target - current) < 0.15) return
        // AbsoluteRotation receives one live-camera compensation. Android's
        // clockwise radians are converted only at this final SDK boundary.
        label.rotateTo(KakaoMarkerGeometry.orientationRadians(target), if (animated && userHasOrientation) 90 else 0)
        userHasOrientation = true
    }

    private fun startCameraHeadingWatch() {
        if (watchingCameraHeading || userHeading == null || disposed) return
        watchingCameraHeading = true
        Choreographer.getInstance().postFrameCallback(cameraHeadingFrame)
    }

    private fun stopCameraHeadingWatch() {
        watchingCameraHeading = false
        Choreographer.getInstance().removeFrameCallback(cameraHeadingFrame)
    }

    private fun applyCamera(raw: Map<*, *>) {
        val kakaoMap = map ?: return
        val lat = (raw["latitude"] as? Number)?.toDouble() ?: return
        val lon = (raw["longitude"] as? Number)?.toDouble() ?: return
        val zoom = (raw["zoom"] as? Number)?.toInt() ?: 14
        val bearing = (raw["bearing"] as? Number)?.toDouble() ?: 0.0
        val pitch = (raw["pitch"] as? Number)?.toDouble() ?: 0.0
        val camera = CameraPosition.from(lat, lon, zoom,
            pitch * PI / 180, bearing * PI / 180, 0.0)
        kakaoMap.moveCamera(CameraUpdateFactory.newCameraPosition(camera))
    }

    private fun applyPadding() {
        map?.setPadding(0, 0, 0,
            (bottomPadding * context.resources.displayMetrics.density).toInt())
    }

    private fun cameraEvent(position: CameraPosition?) {
        if (position == null) return
        event(mapOf("type" to "camera", "latitude" to position.position.latitude,
            "longitude" to position.position.longitude, "zoom" to position.zoomLevel,
            "bearing" to position.rotationAngle * 180 / PI,
            "pitch" to position.tiltAngle * 180 / PI))
    }

    private fun event(payload: Map<String, Any>) {
        if (disposed) return
        val diagnostic = if (payload["type"] == "loaded" || payload["type"] == "failed") {
            payload + mapOf("keyPresent" to keyPresent, "sdkInitialized" to sdkInitialized,
                "stage" to payload["type"]!!)
        } else payload
        channel.invokeMethod("event", diagnostic)
    }

    fun pause() { stopCameraHeadingWatch(); if (!disposed) mapView.pause() }
    fun resume() { if (!disposed) { mapView.resume(); updateUserHeading(false) } }
    override fun getView(): View = mapView
    override fun dispose() {
        if (disposed) return
        disposed = true
        stopCameraHeadingWatch()
        channel.setMethodCallHandler(null)
        mapView.finish()
        map = null
        labels.clear()
        onDisposed(this)
    }
}

internal object KakaoMarkerGeometry {
    fun diameter(kind: String): Double = when (kind) {
        "destination" -> 22.0
        "member", "stale", "ping" -> 18.0
        "user", "userHeading" -> 16.0
        else -> 16.0
    }
    fun scale(value: Double): Double = if (value.isFinite()) kotlin.math.round(value.coerceIn(0.5, 2.0) * 20) / 20 else 1.25
    fun canvas(kind: String, scale: Double = 1.0): Double = when (kind) {
        "user", "userHeading" -> 40.0 * this.scale(scale)
        "member", "stale" -> maxOf(44.0, (diameter(kind) + 4) * this.scale(scale))
        else -> (diameter(kind) + 4) * this.scale(scale)
    }
    fun orientationRadians(clockwiseDegrees: Double) = (clockwiseDegrees * PI / 180).toFloat()
    fun normalize(value: Double) = ((value % 360) + 360) % 360
    fun display(heading: Double, bearing: Double) = normalize(heading - bearing)
    fun target(current: Double, desired: Double) = current + normalize(desired - current + 180) - 180
}
