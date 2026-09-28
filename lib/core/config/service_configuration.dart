/// Compile-time service settings. Only the derived statuses are passed to UI.
enum ConfigurationStatus { missing, invalid, configured }

class ServiceConfiguration {
  const ServiceConfiguration({
    required this.naverClientId,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.mapboxAccessToken,
  });

  static const appIdentifier = 'com.ybaf100.compass';

  final String naverClientId;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String mapboxAccessToken;

  ConfigurationStatus get naverStatus => _nonEmptyId(naverClientId);

  ConfigurationStatus get supabaseStatus {
    if (supabaseUrl.trim().isEmpty && supabasePublishableKey.trim().isEmpty) {
      return ConfigurationStatus.missing;
    }
    final uri = Uri.tryParse(supabaseUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        !supabasePublishableKey.trim().startsWith('sb_publishable_') ||
        supabasePublishableKey.trim().length <= 'sb_publishable_'.length ||
        supabasePublishableKey.trim().contains(RegExp(r'\s'))) {
      return ConfigurationStatus.invalid;
    }
    return ConfigurationStatus.configured;
  }

  ConfigurationStatus get mapboxStatus {
    if (mapboxAccessToken.trim().isEmpty) return ConfigurationStatus.missing;
    return mapboxAccessToken.trim().startsWith('pk.') &&
            mapboxAccessToken.trim().length > 'pk.'.length &&
            !mapboxAccessToken.trim().contains(RegExp(r'\s'))
        ? ConfigurationStatus.configured : ConfigurationStatus.invalid;
  }

  bool get naverConfigured => naverStatus == ConfigurationStatus.configured;
  bool get supabaseConfigured => supabaseStatus == ConfigurationStatus.configured;
  bool get mapboxConfigured => mapboxStatus == ConfigurationStatus.configured;

  static ConfigurationStatus _nonEmptyId(String value) {
    if (value.trim().isEmpty) return ConfigurationStatus.missing;
    return value.trim().contains(RegExp(r'\s'))
        ? ConfigurationStatus.invalid : ConfigurationStatus.configured;
  }
}
