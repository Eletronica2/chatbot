import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<dynamic> get(String path) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final response = await _httpClient.get(uri, headers: _headers());
    return _handleResponse(response);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final response = await _httpClient.post(
      uri,
      headers: _headers(),
      body: jsonEncode(body ?? {}),
    );
    return _handleResponse(response);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(),
      body: jsonEncode(body ?? {}),
    );
    return _handleResponse(response);
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final response = await _httpClient.put(
      uri,
      headers: _headers(),
      body: jsonEncode(body ?? {}),
    );
    return _handleResponse(response);
  }

  Future<void> delete(String path) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final response = await _httpClient.delete(uri, headers: _headers());
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw ApiException(response.body, statusCode: response.statusCode);
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = authService.accessToken;
    final tenantId = authService.tenantId;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (tenantId != null && tenantId.isNotEmpty) {
      headers['x-tenant-id'] = tenantId;
    }
    return headers;
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    throw ApiException(response.body, statusCode: response.statusCode);
  }
}

final apiClient = ApiClient();

