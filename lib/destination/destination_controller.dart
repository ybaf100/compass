import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/diagnostics.dart';
import '../core/compass/heading_filter.dart';
import '../core/compass/heading_provider.dart';
import '../core/geo_point.dart';
import '../core/location/location_provider.dart';
import '../core/network/network_monitor.dart';
import 'bearing_engine.dart';
import 'destination_model.dart';
import 'destination_store.dart';

enum LocationState {
  checking,
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  acquiring,
  poorAccuracy,
  ready,
  unavailable,
}

class DestinationController extends ChangeNotifier {
  DestinationController({
    required LocationProvider locationProvider,
    required HeadingProvider headingProvider,
    required NetworkMonitor networkMonitor,
    required DestinationStore store,
  }) : _locationProvider = locationProvider,
       _headingProvider = headingProvider,
       _networkMonitor = networkMonitor,
       _store = store;

  final LocationProvider _locationProvider;
  final HeadingProvider _headingProvider;
  final NetworkMonitor _networkMonitor;
  final DestinationStore _store;
  final HeadingFilter _filter = HeadingFilter();

  final ValueNotifier<HeadingReading?> heading = ValueNotifier(null);
  final ValueNotifier<double?> filteredHeading = ValueNotifier(null);

  Destination? destination;
  GeoPoint? selectedPoint;
  String? selectedName;
  LocationFix? location;
  LocationState locationState = LocationState.checking;
  NetworkStatus networkStatus = const NetworkStatus.unknown();
  NetworkState get networkState => networkStatus.state;
  LocationAccess? locationAccess;
  LocationPrecision locationPrecision = LocationPrecision.unknown;
  LocationFailure? locationFailure;
  bool firstFixDelayed = false;
  bool persistenceFailed = false;

  StreamSubscription<LocationFix>? _positions;
  StreamSubscription<bool>? _service;
  StreamSubscription<HeadingReading?>? _headings;
  StreamSubscription<NetworkStatus>? _network;
  Timer? _networkRetry;
  int _networkGeneration = 0;
  int _networkRevision = 0;
  Timer? _firstFixTimeout;
  bool _disposed = false;
  bool _destinationTouched = false;
  int _locationGeneration = 0;
  Future<void> _saveQueue = Future<void>.value();

  double? get distanceMeters => location == null || destination == null
      ? null
      : BearingEngine.distanceMeters(location!.point, destination!.point);

  double? get destinationBearing => location == null || destination == null
      ? null
      : BearingEngine.bearing(location!.point, destination!.point);

  Future<void> start() async {
    _network = _networkMonitor.changes.listen((status) {
      _networkRevision++;
      _networkRetry?.cancel();
      _setNetwork(status);
    }, onError: (Object error) {
      _networkRevision++;
      _setNetwork(const NetworkStatus.unknown(failure: NetworkFailure.plugin));
    });
    unawaited(refreshNetwork());

    _headings = _headingProvider.heading.listen((reading) {
      heading.value = reading;
      if (reading == null) {
        _filter.reset();
        filteredHeading.value = null;
      } else {
        filteredHeading.value = _filter.update(reading.degrees);
      }
    }, onError: (Object error) {
      heading.value = null;
      filteredHeading.value = null;
      _filter.reset();
    });

    _service = _locationProvider.serviceEnabled.listen((enabled) {
      if (enabled) {
        unawaited(refreshLocation());
      } else {
        _locationGeneration++;
        unawaited(_positions?.cancel());
        _positions = null;
        _firstFixTimeout?.cancel();
        location = null;
        locationState = LocationState.serviceDisabled;
        _notify();
      }
    }, onError: (Object error) {
      locationFailure = _locationFailure(error, LocationFailure.accessCheck);
      diagnosticEvent('location.serviceStream', locationFailure!.name);
      locationState = LocationState.unavailable;
      _notify();
    });

    final restored = await _store.load();
    if (!_disposed && !_destinationTouched) {
      destination = restored;
      _notify();
    }
    await refreshLocation(requestPermission: true);
  }

  void _setNetwork(NetworkStatus status) {
    if (_disposed) return;
    networkStatus = status;
    diagnosticEvent('network.state', status.state.name);
    if (status.failure != null) diagnosticEvent('network.failure', status.failure!.name);
    _notify();
  }

  /// Two bounded follow-up checks accommodate NWPathMonitor startup/reconnect
  /// transients. A newer stream event always wins over an in-flight query.
  Future<void> refreshNetwork() async {
    _networkRetry?.cancel();
    final generation = ++_networkGeneration;
    _setNetwork(const NetworkStatus.unknown());
    await _checkNetwork(generation, 0);
  }

  Future<void> _checkNetwork(int generation, int attempt) async {
    final revision = _networkRevision;
    NetworkStatus status;
    try {
      status = await _networkMonitor.current.timeout(const Duration(seconds: 4));
    } catch (error) {
      status = NetworkStatus.unknown(failure: error is TimeoutException
          ? NetworkFailure.timeout : NetworkFailure.plugin);
    }
    if (_disposed || generation != _networkGeneration || revision != _networkRevision) return;
    _setNetwork(status);
    if (status.state != NetworkState.available && attempt < 2) {
      _networkRetry = Timer(Duration(milliseconds: attempt == 0 ? 500 : 1500),
        () => unawaited(_checkNetwork(generation, attempt + 1)));
    }
  }

  Future<void> onAppResume() async {
    await Future.wait([refreshNetwork(), refreshLocation()]);
  }

  Future<void> refreshLocation({bool requestPermission = false}) async {
    final generation = ++_locationGeneration;
    _firstFixTimeout?.cancel();
    await _positions?.cancel();
    _positions = null;
    if (_disposed || generation != _locationGeneration) return;
    location = null;
    locationFailure = null;
    firstFixDelayed = false;
    locationState = LocationState.checking;
    _notify();

    try {
      final access = await _locationProvider.checkAccess(
        requestPermission: requestPermission,
      );
      if (_disposed || generation != _locationGeneration) return;
      locationAccess = access;
      if (_locationProvider is LocationDiagnosticsProvider) {
        locationPrecision = (_locationProvider as LocationDiagnosticsProvider).precision;
      }
      diagnosticEvent('location.access', access.name);
      if (access != LocationAccess.granted) {
        location = null;
        locationState = switch (access) {
          LocationAccess.denied => LocationState.permissionDenied,
          LocationAccess.deniedForever =>
            LocationState.permissionDeniedForever,
          LocationAccess.serviceDisabled => LocationState.serviceDisabled,
          LocationAccess.granted => LocationState.acquiring,
        };
        _notify();
        return;
      }

      locationState = LocationState.acquiring;
      _notify();
      _firstFixTimeout = Timer(const Duration(seconds: 15), () {
        if (!_disposed && generation == _locationGeneration && location == null) {
          firstFixDelayed = true;
          diagnosticEvent('location.firstFix', 'delayed');
          _notify();
        }
      });
      _positions = _locationProvider.positions.listen((fix) {
        if (_disposed || generation != _locationGeneration || !fix.point.isValid) {
          return;
        }
        _firstFixTimeout?.cancel();
        if (location == null) diagnosticEvent('location.firstFix', 'received');
        firstFixDelayed = false;
        locationFailure = null;
        location = fix;
        locationState = fix.accuracyMeters > 65
            ? LocationState.poorAccuracy
            : LocationState.ready;
        unawaited(_updateHeadingLocation(fix));
        _notify();
      }, onError: (Object error) {
        if (_disposed || generation != _locationGeneration) return;
        _firstFixTimeout?.cancel();
        location = null;
        locationFailure = _locationFailure(error, LocationFailure.stream);
        diagnosticEvent('location.stream', locationFailure!.name);
        locationState = _stateForFailure(locationFailure!);
        _notify();
      });
    } catch (error) {
      if (_disposed || generation != _locationGeneration) return;
      _firstFixTimeout?.cancel();
      location = null;
      locationFailure = _locationFailure(error, LocationFailure.accessCheck);
      diagnosticEvent('location.access', locationFailure!.name);
      locationState = _stateForFailure(locationFailure!);
      _notify();
    }
  }

  static LocationFailure _locationFailure(Object error, LocationFailure fallback) => switch (error) {
    LocationProviderException() => error.category,
    MissingPluginException() || PlatformException() => LocationFailure.plugin,
    TimeoutException() => LocationFailure.timeout,
    _ => fallback,
  };

  static LocationState _stateForFailure(LocationFailure failure) => switch (failure) {
    LocationFailure.permissionDenied => LocationState.permissionDenied,
    LocationFailure.serviceDisabled => LocationState.serviceDisabled,
    _ => LocationState.unavailable,
  };

  Future<void> _updateHeadingLocation(LocationFix fix) async {
    try {
      await _headingProvider.updateLocation(
        fix.point.latitude,
        fix.point.longitude,
        fix.altitudeMeters,
      );
    } catch (_) {
      // Android can continue with magnetic heading and displays that limitation.
    }
  }

  Future<void> openAppSettings() => _locationProvider.openAppSettings();
  Future<void> openLocationSettings() =>
      _locationProvider.openLocationSettings();

  void selectPoint(GeoPoint point, {String? name}) {
    if (!point.isValid) return;
    selectedPoint = point;
    selectedName = name;
    _notify();
  }

  void cancelSelection() {
    selectedPoint = null;
    selectedName = null;
    _notify();
  }

  void confirmSelection() {
    final point = selectedPoint;
    if (point == null) return;
    destination = Destination(
      point: point,
      name: selectedName,
      createdAt: DateTime.now().toUtc(),
    );
    _destinationTouched = true;
    selectedPoint = null;
    selectedName = null;
    _notify();
    unawaited(_save());
  }

  void clearDestination() {
    destination = null;
    _destinationTouched = true;
    _notify();
    unawaited(_save());
  }

  Future<void> _save() async {
    final snapshot = destination;
    final operation = _saveQueue.then((_) => _store.save(snapshot));
    _saveQueue = operation.catchError((Object _) {});
    try {
      await operation;
      if (_disposed || destination != snapshot) return;
      persistenceFailed = false;
      _notify();
    } catch (_) {
      if (_disposed || destination != snapshot) return;
      persistenceFailed = true;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _networkGeneration++;
    _networkRetry?.cancel();
    _locationGeneration++;
    _firstFixTimeout?.cancel();
    unawaited(_positions?.cancel());
    unawaited(_service?.cancel());
    unawaited(_headings?.cancel());
    unawaited(_network?.cancel());
    heading.dispose();
    filteredHeading.dispose();
    super.dispose();
  }
}
