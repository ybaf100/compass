import 'package:connectivity_plus/connectivity_plus.dart';

abstract class NetworkMonitor {
  Future<bool> get hasConnection;
  Stream<bool> get changes;
}

class ConnectivityNetworkMonitor implements NetworkMonitor {
  final Connectivity _connectivity = Connectivity();

  @override
  Future<bool> get hasConnection async =>
      _connected(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_connected).distinct();

  static bool _connected(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
