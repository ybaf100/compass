import 'package:flutter/foundation.dart';

/// Call sites pass enum names / fixed categories only, never exception text,
/// coordinates, credentials, backend URLs or user/member identifiers.
void diagnosticEvent(String event, String category) {
  if (kDebugMode) debugPrint('[passcom] $event: $category');
}
