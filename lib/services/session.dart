import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppUser {
  final int id;
  final String name;
  final String username;

  /// Rol en el negocio actual: admin o member.
  final String role;
  final bool active;

  /// Dueño de la plataforma (crea negocios desde el portal web).
  final bool isSuperadmin;

  /// Puede usar también el portal web en el negocio actual.
  final bool webAccess;

  const AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.active = true,
    this.isSuperadmin = false,
    this.webAccess = false,
  });

  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, Object?> j) => AppUser(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        username: j['username'] as String,
        role: j['role'] as String,
        active: j['active'] as bool? ?? true,
        isSuperadmin: j['is_superadmin'] as bool? ?? false,
        webAccess: j['web_access'] as bool? ?? false,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'role': role,
        'active': active,
        'is_superadmin': isSuperadmin,
        'web_access': webAccess,
      };
}

/// Un negocio en el que trabaja el usuario, con su rol en él.
class BusinessRef {
  final int id;
  final String name;
  final String role;

  const BusinessRef({required this.id, required this.name, required this.role});

  bool get isAdmin => role == 'admin';

  factory BusinessRef.fromJson(Map<String, Object?> j) => BusinessRef(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        role: j['role'] as String? ?? 'member',
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'role': role};
}

/// Sesión iniciada en el servidor, ligada a un negocio. Se guarda en el
/// dispositivo para poder abrir la app y trabajar sin conexión.
class Session {
  final String serverUrl;
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final AppUser user;
  final int businessId;
  final String businessName;

  /// Todos los negocios en los que trabaja el usuario.
  final List<BusinessRef> businesses;

  /// Hasta qué cambio del servidor tiene este dispositivo (del negocio actual).
  final int cursor;

  const Session({
    required this.serverUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.user,
    required this.businessId,
    required this.businessName,
    this.businesses = const [],
    this.cursor = 0,
  });

  bool get hasSeveralBusinesses => businesses.length > 1;

  /// Construye la sesión a partir de la respuesta de login/setup/refresh/switch.
  factory Session.fromApi(String serverUrl, Map<String, Object?> j, {int cursor = 0}) {
    final business = j['business'] as Map<String, Object?>;
    return Session(
      serverUrl: serverUrl,
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String,
      // Margen de un minuto para renovar antes de que caduque.
      accessExpiresAt: DateTime.now()
          .add(Duration(seconds: (j['expires_in'] as num).toInt() - 60)),
      user: AppUser.fromJson(j['user'] as Map<String, Object?>),
      businessId: (business['id'] as num).toInt(),
      businessName: business['name'] as String,
      businesses: [
        for (final b in (j['businesses'] as List? ?? const []))
          BusinessRef.fromJson(b as Map<String, Object?>),
      ],
      cursor: cursor,
    );
  }

  Session copyWith({int? cursor}) => Session(
        serverUrl: serverUrl,
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessExpiresAt: accessExpiresAt,
        user: user,
        businessId: businessId,
        businessName: businessName,
        businesses: businesses,
        cursor: cursor ?? this.cursor,
      );

  factory Session.fromJson(Map<String, Object?> j) => Session(
        serverUrl: j['server_url'] as String,
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        accessExpiresAt: DateTime.parse(j['access_expires_at'] as String),
        user: AppUser.fromJson(j['user'] as Map<String, Object?>),
        businessId: (j['business_id'] as num).toInt(),
        businessName: j['business_name'] as String,
        businesses: [
          for (final b in (j['businesses'] as List? ?? const []))
            BusinessRef.fromJson(b as Map<String, Object?>),
        ],
        cursor: (j['cursor'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() => {
        'server_url': serverUrl,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'access_expires_at': accessExpiresAt.toIso8601String(),
        'user': user.toJson(),
        'business_id': businessId,
        'business_name': businessName,
        'businesses': [for (final b in businesses) b.toJson()],
        'cursor': cursor,
      };
}

/// Dónde se guarda la sesión. En la app, SharedPreferences; en pruebas, memoria.
abstract class SessionStore {
  Future<Session?> load();
  Future<void> save(Session session);
  Future<void> clear();

  /// Último servidor usado (se conserva al cerrar sesión).
  Future<String?> lastServerUrl();
  Future<void> setLastServerUrl(String url);

  /// Negocio al que pertenecían los datos del dispositivo antes de que cada
  /// negocio tuviera su propia base local (para adoptar esos datos).
  Future<int?> localBusinessId();
  Future<void> setLocalBusinessId(int? id);

  /// Punto de sincronización de cada negocio (al cambiar de uno a otro).
  Future<int> cursorFor(int businessId);
  Future<void> setCursorFor(int businessId, int cursor);
  Future<void> clearCursors();
}

class PrefsSessionStore implements SessionStore {
  static const _session = 'session';
  static const _server = 'server_url';
  static const _business = 'local_business_id';
  static const _cursorPrefix = 'cursor_';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<Session?> load() async {
    final raw = (await _prefs).getString(_session);
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Session session) async =>
      (await _prefs).setString(_session, jsonEncode(session.toJson()));

  @override
  Future<void> clear() async => (await _prefs).remove(_session);

  @override
  Future<String?> lastServerUrl() async => (await _prefs).getString(_server);

  @override
  Future<void> setLastServerUrl(String url) async => (await _prefs).setString(_server, url);

  @override
  Future<int?> localBusinessId() async => (await _prefs).getInt(_business);

  @override
  Future<void> setLocalBusinessId(int? id) async {
    final prefs = await _prefs;
    id == null ? await prefs.remove(_business) : await prefs.setInt(_business, id);
  }

  @override
  Future<int> cursorFor(int businessId) async =>
      (await _prefs).getInt('$_cursorPrefix$businessId') ?? 0;

  @override
  Future<void> setCursorFor(int businessId, int cursor) async =>
      (await _prefs).setInt('$_cursorPrefix$businessId', cursor);

  @override
  Future<void> clearCursors() async {
    final prefs = await _prefs;
    for (final key in prefs.getKeys().where((k) => k.startsWith(_cursorPrefix)).toList()) {
      await prefs.remove(key);
    }
  }
}

class MemorySessionStore implements SessionStore {
  Session? _session;
  String? _server;
  int? _business;
  final _cursors = <int, int>{};

  @override
  Future<Session?> load() async => _session;
  @override
  Future<void> save(Session session) async => _session = session;
  @override
  Future<void> clear() async => _session = null;
  @override
  Future<String?> lastServerUrl() async => _server;
  @override
  Future<void> setLastServerUrl(String url) async => _server = url;
  @override
  Future<int?> localBusinessId() async => _business;
  @override
  Future<void> setLocalBusinessId(int? id) async => _business = id;
  @override
  Future<int> cursorFor(int businessId) async => _cursors[businessId] ?? 0;
  @override
  Future<void> setCursorFor(int businessId, int cursor) async => _cursors[businessId] = cursor;
  @override
  Future<void> clearCursors() async => _cursors.clear();
}
