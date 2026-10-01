import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:destination_compass/map/map_provider.dart';
import 'package:destination_compass/map/mapbox_offline_map_provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:flutter_test/flutter_test.dart';

class FakeCircleManager implements mb.CircleAnnotationManager {
  final annotations = <String, mb.CircleAnnotation>{};
  int created = 0;
  int updated = 0;
  @override
  Future<mb.CircleAnnotation> create(mb.CircleAnnotationOptions o) async {
    final annotation = mb.CircleAnnotation(id: 'circle-${created++}', geometry: o.geometry,
      circleRadius: o.circleRadius, circleColor: o.circleColor,
      circleOpacity: o.circleOpacity, circleStrokeWidth: o.circleStrokeWidth);
    annotations[annotation.id] = annotation;
    return annotation;
  }
  @override
  Future<void> update(mb.CircleAnnotation annotation) async { updated++; }
  @override
  Future<void> delete(mb.CircleAnnotation annotation) async { annotations.remove(annotation.id); }
  @override
  mb.Cancelable tapEvents({required Function(mb.CircleAnnotation) onTap}) => FakeCancelable();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class FakePointManager implements mb.PointAnnotationManager {
  final annotations = <String, mb.PointAnnotation>{};
  int created = 0;
  @override
  Future<mb.PointAnnotation> create(mb.PointAnnotationOptions o) async {
    final annotation = mb.PointAnnotation(id: 'text-${created++}', geometry: o.geometry,
      textSize: o.textSize, textField: o.textField);
    annotations[annotation.id] = annotation;
    return annotation;
  }
  @override
  Future<void> update(mb.PointAnnotation annotation) async {}
  @override
  Future<void> delete(mb.PointAnnotation annotation) async { annotations.remove(annotation.id); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class FakeCancelable implements mb.Cancelable {
  @override
  void cancel() {}
}
class FakeMapboxMap implements mb.MapboxMap {
  int cameraMoves = 0;
  @override
  Future<void> setCamera(mb.CameraOptions options) async { cameraMoves++; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('live Mapbox scale retains map, annotations, camera and minimum friend hit target', () async {
    final circles = FakeCircleManager();
    final texts = FakePointManager();
    final hits = FakeCircleManager();
    var factoryCalls = 0;
    final provider = MapboxOfflineMapProvider(createOverlays: (_) async {
      factoryCalls++;
      return MapboxOverlayManagers(circles, texts, hits);
    });
    expect(provider.markerScale, 1);
    const point = GeoPoint(37, 127);
    const camera = MapCameraState(point, zoom: 16, bearing: 90, pitch: 30);
    await provider.restoreCamera(camera);
    final widget = provider.buildMap(bottomPadding: 0, onPicked: (_) {},
      onNamedPlacePicked: (_, _) {}, onLoaded: () {}, onGesture: () {}) as mb.MapWidget;
    final nativeMap = FakeMapboxMap();
    widget.onMapCreated!(nativeMap);
    await Future<void>.delayed(Duration.zero);
    await provider.setMembers([MapMemberOverlay(id: 'f', name: 'friend',
      point: point, updatedAt: DateTime.utc(2026), isStale: false)]);
    await provider.setDestination(Destination(point: point, createdAt: DateTime.utc(2026)));
    final ids = circles.annotations.keys.toList();
    final cameras = nativeMap.cameraMoves;
    final created = circles.created;
    await provider.setMarkerScale(.5);
    expect(circles.annotations.values.every((a) => a.circleRadius == 5.5), isTrue);
    expect(hits.annotations.values.single.circleRadius, 22);
    expect(circles.annotations.keys.toList(), ids);
    expect(circles.created, created);
    expect(factoryCalls, 1);
    expect(nativeMap.cameraMoves, cameras);
    expect(provider.cameraState, same(camera));
    await provider.setMarkerScale(2);
    expect(circles.annotations.values.every((a) => a.circleRadius == 22), isTrue);
    expect(texts.annotations.values.every((a) => a.textSize == 24), isTrue);
    await provider.setMembers([]);
    expect(hits.annotations, isEmpty);
    provider.dispose();
  });
}
