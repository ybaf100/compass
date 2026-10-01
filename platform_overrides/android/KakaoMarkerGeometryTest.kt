package com.ybaf100.compass

import org.junit.Assert.assertEquals
import org.junit.Test

class KakaoMarkerGeometryTest {
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
