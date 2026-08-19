import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../application/session_controller.dart';
import '../../data/security/token_store.dart';
import '../../domain/expense.dart';
import '../../domain/session.dart';
import 'api_models.dart';
import 'http_transport.dart';

Map<String, Object?> responseObject(Object? value) {
  if (value is! Map) {
    throw const FormatException('The API response must be a JSON object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

final class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.retryAfter,
  });

  final int statusCode;
  final String code;
  final String message;
  final Duration? retryAfter;

  bool get isTransient => statusCode == 429 || statusCode >= 500;
  bool get isAuthenticationFailure => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

final class AuthenticationExpiredException implements Exception {
  const AuthenticationExpiredException();

  @override
  String toString() => 'The stored session can no longer be refreshed.';
}

ApiException apiExceptionFrom(TransportResponse response) {
  var code = 'HTTP_${response.statusCode}';
  var message = 'The API request failed.';
  final body = response.data;
  if (body is Map) {
    final error = body['error'];
    if (error is Map) {
      if (error['code'] is String) {
        code = error['code'] as String;
      }
      if (error['message'] is String) {
        message = error['message'] as String;
      }
    }
  }
  return ApiException(
    statusCode: response.statusCode,
    code: code,
    message: message,
    retryAfter: _parseRetryAfter(response.firstHeader('retry-after')),
  );
}

Duration? _parseRetryAfter(String? value) {
  if (value == null) {
    return null;
  }
  final seconds = int.tryParse(value);
  if (seconds != null && seconds >= 0) {
    return Duration(seconds: seconds);
  }
  final date = DateTime.tryParse(value)?.toUtc();
  if (date == null) {
    return null;
  }
  final difference = date.difference(DateTime.now().toUtc());
  return difference.isNegative ? Duration.zero : difference;
}

final class AuthenticatedApiClient {
  AuthenticatedApiClient({
    required this._transport,
    required this._tokenStore,
    required this._sessionController,
  });

  final HttpTransport _transport;
  final TokenStore _tokenStore;
  final SessionController _sessionController;
  Future<SessionTokens>? _refreshInFlight;

  Future<TransportResponse> send(TransportRequest request) async {
    final currentTokens = await _tokenStore.read();
    if (currentTokens == null) {
      _sessionController.markSignedOut();
      throw const AuthenticationExpiredException();
    }

    final first = await _transport.send(
      request.withAuthorization(currentTokens.accessToken),
    );
    if (first.statusCode != 401) {
      return first;
    }

    final refreshed = await _refreshOnce();
    final retry = await _transport.send(
      request.withAuthorization(refreshed.accessToken),
    );
    if (retry.statusCode == 401) {
      await _expireSession();
      throw const AuthenticationExpiredException();
    }
    return retry;
  }

  Future<SessionTokens> _refreshOnce() {
    final active = _refreshInFlight;
    if (active != null) {
      return active;
    }
    final completer = Completer<SessionTokens>();
    _refreshInFlight = completer.future;
    () async {
      try {
        final current = await _tokenStore.read();
        if (current == null) {
          throw const AuthenticationExpiredException();
        }
        final response = await _transport.send(
          TransportRequest(
            method: 'POST',
            path: '/v1/auth/refresh',
            data: <String, Object?>{'refreshToken': current.refreshToken},
          ),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw const AuthenticationExpiredException();
        }
        final auth = AuthResponseDto.fromJson(responseObject(response.data));
        await _tokenStore.write(auth.tokens);
        _sessionController.markSignedIn();
        completer.complete(auth.tokens);
      } catch (error, stackTrace) {
        await _expireSession();
        completer.completeError(error, stackTrace);
      } finally {
        _refreshInFlight = null;
      }
    }();
    return completer.future;
  }

  Future<void> _expireSession() async {
    await _tokenStore.clear();
    _sessionController.markSignedOut();
  }
}

abstract interface class ExpenseSyncApi {
  Future<List<MutationResultDto>> pushMutations(
    List<MutationCandidateDto> mutations,
  );

  Future<ChangePageDto> pullChanges({String? cursor, required int limit});

  Future<BootstrapPageDto> bootstrap({String? pageToken, required int limit});
}

final class DioExpenseSyncApi implements ExpenseSyncApi {
  const DioExpenseSyncApi(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<List<MutationResultDto>> pushMutations(
    List<MutationCandidateDto> mutations,
  ) async {
    final response = await _client.send(
      TransportRequest(
        method: 'POST',
        path: '/v1/sync/mutations',
        data: <String, Object?>{
          'mutations': mutations
              .map((mutation) => mutation.toJson())
              .toList(growable: false),
        },
      ),
    );
    final body = _successfulObject(response);
    final results = body['results'];
    if (results is! List) {
      throw const FormatException('results must be an array.');
    }
    final parsed = results
        .map((item) => MutationResultDto.fromJson(responseObject(item)))
        .toList(growable: false);
    _debugSyncLog('sync_push', <String, Object?>{
      'requestId': response.firstHeader('x-request-id'),
      'mutationIds': mutations
          .map((mutation) => mutation.mutationId)
          .toList(growable: false),
      'statuses': parsed
          .map((result) => result.status.name.toUpperCase())
          .toList(growable: false),
    });
    return parsed;
  }

  @override
  Future<ChangePageDto> pullChanges({
    String? cursor,
    required int limit,
  }) async {
    final response = await _client.send(
      TransportRequest(
        method: 'GET',
        path: '/v1/sync/changes',
        queryParameters: <String, Object?>{'cursor': ?cursor, 'limit': limit},
      ),
    );
    final page = ChangePageDto.fromJson(_successfulObject(response));
    _debugSyncLog('sync_pull', <String, Object?>{
      'requestId': response.firstHeader('x-request-id'),
      'changeCount': page.changes.length,
      'nextCursor': _cursorPreview(page.nextCursor),
      'hasMore': page.hasMore,
    });
    return page;
  }

  @override
  Future<BootstrapPageDto> bootstrap({
    String? pageToken,
    required int limit,
  }) async {
    final response = await _client.send(
      TransportRequest(
        method: 'GET',
        path: '/v1/sync/bootstrap',
        queryParameters: <String, Object?>{
          'pageToken': ?pageToken,
          'limit': limit,
        },
      ),
    );
    final page = BootstrapPageDto.fromJson(_successfulObject(response));
    _debugSyncLog('sync_bootstrap', <String, Object?>{
      'requestId': response.firstHeader('x-request-id'),
      'itemCount': page.items.length,
      'watermarkCursor': _cursorPreview(page.watermarkCursor),
      'hasMore': page.hasMore,
    });
    return page;
  }

  Map<String, Object?> _successfulObject(TransportResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFrom(response);
    }
    return responseObject(response.data);
  }
}

String _cursorPreview(String value) {
  const visibleLength = 16;
  return value.length <= visibleLength
      ? value
      : '${value.substring(0, visibleLength)}…';
}

void _debugSyncLog(String event, Map<String, Object?> fields) {
  if (kDebugMode) {
    debugPrint(jsonEncode(<String, Object?>{'event': event, ...fields}));
  }
}

abstract interface class AuthenticationApi {
  Future<AuthResponseDto> login(HouseholdMember member, String pin);

  Future<void> logout(SessionTokens tokens);
}

final class DioAuthenticationApi implements AuthenticationApi {
  const DioAuthenticationApi(this._transport);

  final HttpTransport _transport;

  @override
  Future<AuthResponseDto> login(HouseholdMember member, String pin) async {
    final response = await _transport.send(
      TransportRequest(
        method: 'POST',
        path: '/v1/auth/login',
        data: <String, Object?>{'member': member.wireName, 'pin': pin},
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFrom(response);
    }
    return AuthResponseDto.fromJson(responseObject(response.data));
  }

  @override
  Future<void> logout(SessionTokens tokens) async {
    final response = await _transport.send(
      TransportRequest(
        method: 'POST',
        path: '/v1/auth/logout',
        data: <String, Object?>{'refreshToken': tokens.refreshToken},
      ).withAuthorization(tokens.accessToken),
    );
    if (response.statusCode == 204 || response.statusCode == 401) {
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFrom(response);
    }
  }
}

/// Tells the API which device to wake when the other member changes something.
abstract interface class DeviceRegistrationApi {
  /// Claims this device's push token for the signed-in member.
  ///
  /// Idempotent by token: the server upserts, so a repeat registration is a
  /// no-op, and a token that moved to the other member follows whoever signed in
  /// last.
  Future<void> register(String token);

  /// Gives the token up, so a signed-out phone stops being woken.
  Future<void> unregister(String token);
}

final class DioDeviceRegistrationApi implements DeviceRegistrationApi {
  const DioDeviceRegistrationApi(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<void> register(String token) => _send('/v1/devices', <String, Object?>{
    'token': token,
    // The only platform the API accepts. Sent explicitly rather than defaulted
    // server-side so the day iOS exists, an old build cannot be mistaken for it.
    'platform': 'ANDROID',
  });

  @override
  Future<void> unregister(String token) =>
      _send('/v1/devices/unregister', <String, Object?>{'token': token});

  Future<void> _send(String path, Map<String, Object?> data) async {
    final response = await _client.send(
      TransportRequest(method: 'POST', path: path, data: data),
    );
    if (response.statusCode == 204) {
      return;
    }
    // Thrown rather than swallowed here. The caller is what decides that a
    // failed registration is survivable, and it needs to know the attempt failed
    // so it can leave the local timestamp null and retry on the next launch.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw apiExceptionFrom(response);
    }
  }
}
