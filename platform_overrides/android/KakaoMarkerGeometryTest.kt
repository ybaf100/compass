package com.ybaf100.compass

import org.junit.Assert.assertEquals
import org.junit.Test

class KakaoMarkerGeometryTest {
    @Test fun northUpNorth() { assertEquals(0.0, KakaoMarkerGeometry.display(0.0, 0.0), 0.001) }
    @Test fun cameraEastDeviceEast() { assertEquals(0.0, KakaoMarkerGeometry.display(90.0, 90.0), 0.001) }
    @Test fun cameraEastDeviceNorth() { assertEquals(270.0, KakaoMarkerGeometry.display(0.0, 90.0), 0.001) }
    @Test fun cameraEastDeviceSouth() { assertEquals(90.0, KakaoMarkerGeometry.display(180.0, 90.0), 0.001) }
    @Test fun finalBoundaryRadians() { assertEquals((Math.PI / 2).toFloat(), KakaoMarkerGeometry.orientationRadians(90.0), 0.001f) }
    @Test fun scaleClampAndDefaultPreset() {
        assertEquals(0.5, KakaoMarkerGeometry.scale(0.0), 0.001)
        assertEquals(2.0, KakaoMarkerGeometry.scale(3.0), 0.001)
        assertEquals(1.25, KakaoMarkerGeometry.scale(1.25), 0.001)
    }
    @Test fun allScalesPreserveTouchArea() {
        for (scale in listOf(0.5, 1.0, 1.25, 2.0)) {
            for (kind in listOf("member", "stale")) {
                org.junit.Assert.assertTrue(KakaoMarkerGeometry.canvas(kind, scale) >= 44)
                org.junit.Assert.assertTrue(KakaoMarkerGeometry.diameter(kind) * scale < KakaoMarkerGeometry.diameter("destination") * scale)
            }
            assertEquals(40 * scale, KakaoMarkerGeometry.canvas("userHeading", scale), 0.001)
        }
    }
    @Test fun northUpEast() { assertEquals(90.0, KakaoMarkerGeometry.display(90.0, 0.0), 0.001) }
    @Test fun rotatedCamera() { assertEquals(45.0, KakaoMarkerGeometry.display(90.0, 45.0), 0.001) }
    @Test fun cameraWrap() { assertEquals(1.0, KakaoMarkerGeometry.display(0.0, 359.0), 0.001) }
    @Test fun forwardWrap() { assertEquals(360.0, KakaoMarkerGeometry.target(359.0, 0.0), 0.001) }
    @Test fun reverseWrap() { assertEquals(-1.0, KakaoMarkerGeometry.target(0.0, 359.0), 0.001) }
    @Test fun continuousTurn() { assertEquals(720.0, KakaoMarkerGeometry.target(719.0, 0.0), 0.001) }
    @Test fun smallMarkers() {
        assertEquals(22.0, KakaoMarkerGeometry.diameter("destination"), 0.001)
        for (kind in listOf("member", "stale", "ping")) assertEquals(18.0, KakaoMarkerGeometry.diameter(kind), 0.001)
        assertEquals(16.0, KakaoMarkerGeometry.diameter("candidate"), 0.001)
    }
    @Test fun peerTouchArea() {
        for (kind in listOf("member", "stale")) assertEquals(44.0, KakaoMarkerGeometry.canvas(kind), 0.001)
    }
    @Test fun centeredDirectionDot() {
        assertEquals(16.0, KakaoMarkerGeometry.diameter("user"), 0.001)
        assertEquals(40.0, KakaoMarkerGeometry.canvas("userHeading"), 0.001)
        assertEquals(KakaoMarkerGeometry.canvas("user"), KakaoMarkerGeometry.canvas("userHeading"), 0.001)
    }
}
