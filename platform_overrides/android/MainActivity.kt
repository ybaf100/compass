package com.ybaf100.compass

import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI

class MainActivity : FlutterActivity(), SensorEventListener {
    private var kakaoFactory: KakaoMapViewFactory? = null
    private var sensorManager: SensorManager? = null
    private var headingSensor: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null
    private var declination: Float? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        kakaoFactory = KakaoMapViewFactory(this, flutterEngine.dartExecutor.binaryMessenger)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "app.destination_compass/kakao_map", kakaoFactory!!)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,
            "app.destination_compass/heading").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                startHeading()
            }

            override fun onCancel(arguments: Any?) {
                stopHeading()
                eventSink = null
            }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "app.destination_compass/heading_control").setMethodCallHandler { call, result ->
            if (call.method != "updateLocation") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val latitude = call.argument<Number>("latitude")?.toDouble()
            val longitude = call.argument<Number>("longitude")?.toDouble()
            val altitude = call.argument<Number>("altitude")?.toFloat()
            if (latitude == null || longitude == null || altitude == null) {
                result.error("INVALID_LOCATION", "A GPS fix is required", null)
                return@setMethodCallHandler
            }
            declination = GeomagneticField(latitude.toFloat(), longitude.toFloat(),
                altitude, System.currentTimeMillis()).declination
            result.success(null)
        }
    }

    private fun startHeading() {
        val manager = sensorManager ?: return
        val sensor = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: manager.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
        headingSensor = sensor
        if (sensor == null) {
            eventSink?.success(null)
            return
        }
        manager.unregisterListener(this)
        if (!manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)) {
            eventSink?.success(null)
        }
    }

    private fun stopHeading() {
        sensorManager?.unregisterListener(this)
        headingSensor = null
    }

    override fun onPause() {
        kakaoFactory?.pause()
        stopHeading()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        kakaoFactory?.resume()
        if (eventSink != null) startHeading()
    }

    override fun onDestroy() {
        kakaoFactory?.dispose()
        kakaoFactory = null
        stopHeading()
        eventSink = null
        super.onDestroy()
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor != headingSensor || event.values.size < 3) return
        val rotation = FloatArray(9)
        val displayRotation = FloatArray(9)
        SensorManager.getRotationMatrixFromVector(rotation, event.values)
        val (axisX, axisY) = when (windowManager.defaultDisplay.rotation) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        if (!SensorManager.remapCoordinateSystem(rotation, axisX, axisY, displayRotation)) return
        val orientation = FloatArray(3)
        SensorManager.getOrientation(displayRotation, orientation)
        val magneticDegrees = orientation[0] * 180.0 / PI
        val correction = declination
        val trueDegrees = (magneticDegrees + (correction ?: 0f) + 360.0) % 360.0
        val rawAccuracy = event.values.getOrNull(4)
        val accuracy = if (rawAccuracy != null && rawAccuracy.isFinite() && rawAccuracy >= 0f)
            rawAccuracy * 180.0 / PI else null
        eventSink?.success(mapOf(
            "heading" to trueDegrees,
            "trueNorth" to (correction != null),
            "accuracy" to accuracy
        ))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (sensor == headingSensor && accuracy == SensorManager.SENSOR_STATUS_UNRELIABLE) {
            eventSink?.success(null)
        }
    }
}
