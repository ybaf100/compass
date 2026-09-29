package com.ybaf100.compass

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
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
    private var pendingMarkers: List<Map<*, *>> = emptyList()
    private var pendingCamera: Map<*, *>? = null
    private var bottomPadding = 0.0
    private var disposed = false
    private var failed = false

    init {
        channel.setMethodCallHandler(::handle)
        if (appKey.isBlank()) {
            failed = true
            event(mapOf("type" to "failed"))
        } else {
            try {
                KakaoMapSdk.init(context.applicationContext, appKey)
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
                            if (gesture != GestureType.Unknown) event(mapOf("type" to "gesture"))
                        }
                        kakaoMap.setOnCameraMoveEndListener { _, position, _ -> cameraEvent(position) }
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
                    result.success(if (map != null) "loaded" else if (failed) "failed" else "initializing")
                    return
                }
                "overlays" -> {
                    pendingMarkers = (call.argument<List<*>>("markers") ?: emptyList<Any>())
                        .mapNotNull { it as? Map<*, *> }
                    applyMarkers()
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
        val palette = mapOf("user" to 0xFF328DFF.toInt(),
            "candidate" to 0xFF3970DF.toInt(), "destination" to 0xFFED6541.toInt(),
            "member" to 0xFF2EBF9F.toInt(), "stale" to 0xFF8796A0.toInt(),
            "ping" to 0xFFF0AF40.toInt())
        val manager = kakaoMap.labelManager ?: return
        for ((kind, color) in palette) {
            val style = LabelStyles.from(LabelStyle.from(icon(color))
                .setTextStyles(13, Color.WHITE, 3, Color.BLACK))
            manager.addLabelStyles(style)?.let { styles[kind] = it }
        }
    }

    private fun icon(color: Int): Bitmap {
        val size = (32 * context.resources.displayMetrics.density).toInt().coerceAtLeast(32)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.WHITE
        canvas.drawCircle(size / 2f, size / 2f, size * 0.44f, paint)
        paint.color = color
        canvas.drawCircle(size / 2f, size / 2f, size * 0.36f, paint)
        return bitmap
    }

    private fun applyMarkers() {
        val kakaoMap = map ?: return
        val layer = kakaoMap.labelManager?.layer ?: return
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
            val style = styles[kind] ?: continue
            val caption = marker["label"] as? String ?: ""
            val existing = labels[id]
            if (existing == null) {
                labels[id] = layer.addLabel(LabelOptions.from(id, position)
                    .setStyles(style).setTexts(LabelTextBuilder().setTexts(caption))
                    .setClickable(id.startsWith("member:")))
            } else {
                if (existing.position != position) {
                    // Dart's MemberMarkerMotion already interpolates short moves.
                    existing.moveTo(position)
                }
                if (kinds[id] != kind) existing.setStyles(style)
                existing.setTexts(LabelTextBuilder().setTexts(caption))
                existing.invalidate()
            }
            kinds[id] = kind
        }
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
        if (!disposed) channel.invokeMethod("event", payload)
    }

    fun pause() { if (!disposed) mapView.pause() }
    fun resume() { if (!disposed) mapView.resume() }
    override fun getView(): View = mapView
    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        mapView.finish()
        map = null
        labels.clear()
        onDisposed(this)
    }
}
