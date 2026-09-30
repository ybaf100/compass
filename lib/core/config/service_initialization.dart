import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../diagnostics.dart';

enum InitializationState { notConfigured, initializing, initialized, failed }
enum InitializationFailure { authentication, configuration, network, timeout,
  storage, plugin, unexpected }

class ServiceInitialization {
  const ServiceInitialization(this.state, {this.failure});
  const ServiceInitialization.initialized()
      : state = InitializationState.initialized, failure = null;
  final InitializationState state;
  final InitializationFailure? failure;
}

InitializationFailure classifyInitializationFailure(Object error) => switch (error) {
  TimeoutException() => InitializationFailure.timeout,
  SocketException() => InitializationFailure.network,
  FileSystemException() => InitializationFailure.storage,
  FormatException() || ArgumentError() => InitializationFailure.configuration,
  MissingPluginException() || PlatformException() => InitializationFailure.plugin,
  _ => InitializationFailure.unexpected,
};

/// Does not depend on a connectivity hint; an SDK attempt is authoritative.
Future<ServiceInitialization> initializeService({required bool configured,
  required String service, required Future<void> Function() initialize,
  InitializationFailure Function(Object)? classify,
}) async {
  if (!configured) return const ServiceInitialization(InitializationState.notConfigured);
  try {
    await initialize();
    diagnosticEvent('$service.initialize', 'initialized');
    return const ServiceInitialization.initialized();
  } catch (error) {
    final category = (classify ?? classifyInitializationFailure)(error);
    diagnosticEvent('$service.initialize', category.name);
    return ServiceInitialization(InitializationState.failed, failure: category);
  }
}
