enum KakaoStage {
  platformViewCreated, sdkInitialized, enginePrepareRequested, authenticating,
  enginePrepared, authenticated, engineActivationRequested, engineActivated,
  addViewsRequested, addViewSucceeded, loaded, prepareTimedOut, timedOut, failed,
}
enum KakaoAuthCallback { none, succeeded, failed }
enum KakaoEngineSummary { notCreated, preparing, prepared, active, recovering, failed }

/// Whitelisted native diagnostics only. Raw keys and SDK descriptions are never
/// retained, even if an unexpected field arrives over the platform channel.
class KakaoDiagnostics {
  const KakaoDiagnostics({this.stage, this.stages = const [],
    this.keyPresent = false, this.sdkInitialized = false,
    this.runtimeBundleId, this.authErrorCode, this.retryCount = 0,
    this.retryPending = false, this.width, this.height,
    this.prepareReturn, this.enginePrepared, this.engineActive,
    this.authCallback = KakaoAuthCallback.none, this.engineStateSummary,
    this.stateDescriptionAvailable, this.nativeTimeoutManaged = false});

  final KakaoStage? stage;
  final List<KakaoStage> stages;
  final bool keyPresent;
  final bool sdkInitialized;
  final String? runtimeBundleId;
  final int? authErrorCode;
  final int retryCount;
  final bool retryPending;
  final double? width;
  final double? height;
  final bool? prepareReturn;
  final bool? enginePrepared;
  final bool? engineActive;
  final KakaoAuthCallback authCallback;
  final KakaoEngineSummary? engineStateSummary;
  final bool? stateDescriptionAvailable;
  final bool nativeTimeoutManaged;

  bool? matchesBundleId(String expected) => runtimeBundleId == null
      ? null : runtimeBundleId == expected;

  String get authErrorLabel => switch (authErrorCode) {
    400 => '400 · 요청 파라미터 오류',
    401 => '401 · 인증 자격 증명 오류',
    403 => '403 · 지도 사용 권한 오류',
    429 => '429 · 사용량 한도 초과',
    499 => '499 · 인증 서버 통신 실패',
    null => '없음',
    _ => '$authErrorCode · 기타 인증 오류',
  };

  KakaoDiagnostics withRuntimeBundleId(String? id) => KakaoDiagnostics(
    stage: stage, stages: stages, keyPresent: keyPresent,
    sdkInitialized: sdkInitialized, runtimeBundleId: id,
    authErrorCode: authErrorCode, retryCount: retryCount,
    retryPending: retryPending, width: width, height: height,
    prepareReturn: prepareReturn, enginePrepared: enginePrepared,
    engineActive: engineActive, authCallback: authCallback,
    engineStateSummary: engineStateSummary,
    stateDescriptionAvailable: stateDescriptionAvailable,
    nativeTimeoutManaged: nativeTimeoutManaged);

  KakaoDiagnostics apply(Map<String, dynamic> event) {
    KakaoStage? parseStage(dynamic raw) {
      for (final value in KakaoStage.values) {
        if (value.name == raw) return value;
      }
      return null;
    }
    final history = event['stages'];
    final id = event['runtimeBundleId'];
    bool? boolean(String name, bool? current) => event.containsKey(name) && event[name] == null
        ? null : event[name] is bool ? event[name] as bool : current;
    T? enumeration<T extends Enum>(String name, List<T> values, T? current) {
      for (final value in values) {
        if (value.name == event[name]) return value;
      }
      return current;
    }
    int? integer(String name) => event[name] is num && (event[name] as num).isFinite
        ? (event[name] as num).toInt() : null;
    double? dimension(String name) {
      final raw = event[name];
      return raw is num && raw.isFinite && raw >= 0 ? raw.toDouble() : null;
    }
    return KakaoDiagnostics(
      stage: parseStage(event['stage']) ?? stage,
      stages: history is List ? List.unmodifiable(history.map(parseStage)
          .whereType<KakaoStage>().take(24)) : stages,
      keyPresent: event['keyPresent'] is bool ? event['keyPresent'] as bool : keyPresent,
      sdkInitialized: event['sdkInitialized'] is bool
          ? event['sdkInitialized'] as bool : sdkInitialized,
      runtimeBundleId: id is String ? id : runtimeBundleId,
      authErrorCode: event.containsKey('authErrorCode')
          ? integer('authErrorCode') : authErrorCode,
      retryCount: integer('retryCount') ?? retryCount,
      retryPending: event['retryPending'] is bool
          ? event['retryPending'] as bool : retryPending,
      width: dimension('containerWidth') ?? width,
      height: dimension('containerHeight') ?? height,
      prepareReturn: boolean('prepareReturn', prepareReturn),
      enginePrepared: boolean('enginePrepared', enginePrepared),
      engineActive: boolean('engineActive', engineActive),
      authCallback: enumeration('authCallback', KakaoAuthCallback.values, authCallback)!,
      engineStateSummary: enumeration('engineStateSummary', KakaoEngineSummary.values, engineStateSummary),
      stateDescriptionAvailable: boolean('stateDescriptionAvailable', stateDescriptionAvailable),
      nativeTimeoutManaged: boolean('nativeTimeoutManaged', nativeTimeoutManaged) ?? nativeTimeoutManaged,
    );
  }
}
