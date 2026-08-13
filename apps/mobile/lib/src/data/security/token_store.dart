import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/session.dart';

abstract interface class TokenStore {
  Future<SessionTokens?> read();

  Future<void> write(SessionTokens tokens);

  Future<void> clear();
}

final class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              sharedPreferencesName: 'household_expenses_secure_session',
              preferencesKeyPrefix: 'household_expenses',
              resetOnError: false,
            ),
          );

  static const String _accessTokenKey = 'access_token';
  static const String _accessExpiryKey = 'access_token_expires_at';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _refreshExpiryKey = 'refresh_token_expires_at';

  final FlutterSecureStorage _storage;

  @override
  Future<SessionTokens?> read() async {
    final values = await Future.wait<String?>(<Future<String?>>[
      _storage.read(key: _accessTokenKey),
      _storage.read(key: _accessExpiryKey),
      _storage.read(key: _refreshTokenKey),
      _storage.read(key: _refreshExpiryKey),
    ]);
    if (values.any((value) => value == null)) {
      return null;
    }
    final accessExpiry = DateTime.tryParse(values[1]!);
    final refreshExpiry = DateTime.tryParse(values[3]!);
    if (accessExpiry == null || refreshExpiry == null) {
      await clear();
      return null;
    }
    return SessionTokens(
      accessToken: values[0]!,
      accessTokenExpiresAt: accessExpiry.toUtc(),
      refreshToken: values[2]!,
      refreshTokenExpiresAt: refreshExpiry.toUtc(),
    );
  }

  @override
  Future<void> write(SessionTokens tokens) async {
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(
      key: _accessExpiryKey,
      value: tokens.accessTokenExpiresAt.toUtc().toIso8601String(),
    );
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
    await _storage.write(
      key: _refreshExpiryKey,
      value: tokens.refreshTokenExpiresAt.toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> clear() async {
    await Future.wait<void>(<Future<void>>[
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _accessExpiryKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _refreshExpiryKey),
    ]);
  }
}

final class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.tokens]);

  SessionTokens? tokens;

  @override
  Future<void> clear() async {
    tokens = null;
  }

  @override
  Future<SessionTokens?> read() async => tokens;

  @override
  Future<void> write(SessionTokens tokens) async {
    this.tokens = tokens;
  }
}
