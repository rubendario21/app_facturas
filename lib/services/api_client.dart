import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// El servidor respondió con un error (mensaje listo para mostrar).
class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

/// No se pudo contactar con el servidor (sin conexión, servidor caído...).
class NetworkException implements Exception {
  final String message;
  NetworkException([this.message = 'No hay conexión con el servidor.']);

  @override
  String toString() => message;
}

/// La sesión ya no es válida (caducada, usuario desactivado, contraseña
/// cambiada). Hay que volver a iniciar sesión.
class SessionExpiredException implements Exception {
  @override
  String toString() => 'Tu sesión ha caducado. Vuelve a iniciar sesión.';
}

/// Peticiones JSON a la API.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const timeout = Duration(seconds: 25);

  /// Servidor de producción (API y portal web en /admin).
  static const defaultServerUrl = 'https://movil.peoplecore.com.co';

  /// Normaliza la dirección: añade http:// si falta y quita la barra final.
  static String normalizeUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Future<Map<String, Object?>> send(
    String baseUrl,
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    final http.Response response;
    try {
      response = await http.Response.fromStream(
          await _client.send(request).timeout(timeout));
    } on TimeoutException {
      throw NetworkException('El servidor no responde. Revisa la conexión.');
    } on SocketException {
      throw NetworkException();
    } on http.ClientException {
      throw NetworkException();
    } on FormatException {
      throw NetworkException('La dirección del servidor no es válida.');
    } on ArgumentError {
      throw NetworkException('La dirección del servidor no es válida.');
    }

    Map<String, Object?> json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      json = decoded is Map<String, Object?> ? decoded : {};
    } catch (_) {
      throw ApiException(response.statusCode,
          'La respuesta del servidor no es válida (¿es la dirección correcta de la API?).');
    }
    if (response.statusCode >= 400) {
      throw ApiException(
          response.statusCode,
          json['error'] as String? ??
              'Error del servidor (${response.statusCode}).');
    }
    return json;
  }
}
