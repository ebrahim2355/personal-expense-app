import 'package:flutter/foundation.dart';

final class AppConfig {
  AppConfig._({required this.apiBaseUri});

  static const String _compiledApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  final Uri apiBaseUri;

  String get environmentLabel => kReleaseMode ? 'Production' : 'Development';

  static AppConfig fromEnvironment() {
    final value = _compiledApiBaseUrl.isEmpty
        ? (kReleaseMode ? '' : 'http://10.0.2.2:3000')
        : _compiledApiBaseUrl;
    if (value.isEmpty) {
      throw StateError(
        'API_BASE_URL is required for release builds. Pass it with '
        '--dart-define=API_BASE_URL=https://your-api.example.',
      );
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw StateError('API_BASE_URL must be an absolute HTTP(S) origin.');
    }
    if (uri.scheme != 'https' && !(kDebugMode && uri.scheme == 'http')) {
      throw StateError('API_BASE_URL must use HTTPS outside debug builds.');
    }
    return AppConfig._(apiBaseUri: uri);
  }
}
