import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../diagnostics.dart';

enum NetworkState { unknown, available, unavailable }
enum NetworkFailure { plugin, timeout, unexpected }

class NetworkStatus {
  const NetworkStatus(this.state, {this.failure});
  const NetworkStatus.unknown({this.failure}) : state = NetworkState.unknown;

  final NetworkState state;
  final NetworkFailure? failure;
}

abstract class NetworkMonitor {
  Future<NetworkStatus> get current;
  Stream<NetworkStatus> get changes;
}

class ConnectivityNetworkMonitor implements NetworkMonitor {
  ConnectivityNetworkMonitor({
    Future<List<ConnectivityResult>> Function()? check,
    Stream<List<ConnectivityResult>>? changes,
  }) : _check = check ?? Connectivity().checkConnectivity,
       _changes = changes ?? Connectivity().onConnectivityChanged;

  final Future<List<ConnectivityResult>> Function() _check;
  final Stream<List<ConnectivityResult>> _changes;

  @override
  Future<NetworkStatus> get current async {
    try {
      return normalize(await _check());
    } catch (_) {
      diagnosticEvent('network.check', 'pluginFailure');
      return const NetworkStatus.unknown(failure: NetworkFailure.plugin);
    }
  }

  @override
  Stream<NetworkStatus> get changes => _changes.transform(
    StreamTransformer<List<ConnectivityResult>, NetworkStatus>.fromHandlers(
      handleData: (raw, sink) => sink.add(normalize(raw)),
      handleError: (Object error, StackTrace stack, sink) {
        diagnosticEvent('network.stream', 'pluginFailure');
        sink.add(const NetworkStatus.unknown(failure: NetworkFailure.plugin));
      },
    ),
  ).distinct((a, b) => a.state == b.state && a.failure == b.failure);

  static NetworkStatus normalize(List<ConnectivityResult> results) {
    diagnosticEvent('network.raw', results.map((value) => value.name).join(','));
    final state = results.any((value) => value != ConnectivityResult.none)
        ? NetworkState.available
        : results.contains(ConnectivityResult.none)
            ? NetworkState.unavailable : NetworkState.unknown;
    diagnosticEvent('network.normalized', state.name);
    return NetworkStatus(state);
  }
}
