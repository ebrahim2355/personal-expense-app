import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

final class TransportRequest {
  const TransportRequest({
    required this.method,
    required this.path,
    this.data,
    this.queryParameters = const <String, Object?>{},
    this.headers = const <String, Object?>{},
  });

  final String method;
  final String path;
  final Object? data;
  final Map<String, Object?> queryParameters;
  final Map<String, Object?> headers;

  TransportRequest withAuthorization(String accessToken) => TransportRequest(
    method: method,
    path: path,
    data: data,
    queryParameters: queryParameters,
    headers: <String, Object?>{
      ...headers,
      'Authorization': 'Bearer $accessToken',
    },
  );
}

final class TransportResponse {
  const TransportResponse({
    required this.statusCode,
    required this.data,
    this.headers = const <String, List<String>>{},
  });

  final int statusCode;
  final Object? data;
  final Map<String, List<String>> headers;

  String? firstHeader(String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }
}

abstract interface class HttpTransport {
  Future<TransportResponse> send(TransportRequest request);
}

final class NetworkException implements Exception {
  const NetworkException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'NetworkException: $message';
}

final class DioHttpTransport implements HttpTransport {
  DioHttpTransport(Uri baseUri)
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUri.toString().replaceFirst(RegExp(r'/$'), ''),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 600,
        ),
      );

  final Dio _dio;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final requestId =
        request.headers.entries
            .where((entry) => entry.key.toLowerCase() == 'x-request-id')
            .map((entry) => entry.value.toString())
            .firstOrNull ??
        const Uuid().v4();
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.request<Object?>(
        request.path,
        data: request.data,
        queryParameters: request.queryParameters,
        options: Options(
          method: request.method,
          headers: <String, Object?>{
            ...request.headers,
            'X-Request-ID': requestId,
          },
        ),
      );
      _debugHttpLog(<String, Object?>{
        'event': 'sync_http',
        'requestId': requestId,
        'method': request.method,
        'path': request.path,
        'statusCode': response.statusCode ?? 0,
        'durationMs': stopwatch.elapsedMilliseconds,
      });
      return TransportResponse(
        statusCode: response.statusCode ?? 0,
        data: response.data,
        headers: response.headers.map,
      );
    } on DioException catch (error) {
      _debugHttpLog(<String, Object?>{
        'event': 'sync_http',
        'requestId': requestId,
        'method': request.method,
        'path': request.path,
        'result': 'network_error',
        'durationMs': stopwatch.elapsedMilliseconds,
      });
      throw NetworkException('The API request did not complete.', error);
    }
  }
}

void _debugHttpLog(Map<String, Object?> fields) {
  if (kDebugMode) {
    debugPrint(jsonEncode(fields));
  }
}
