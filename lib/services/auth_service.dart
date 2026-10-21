import 'package:flutter/foundation.dart';

import '../data/database_helper.dart';
import 'api_client.dart';
import 'session.dart';

/// Inicio de sesión contra el servidor, negocio actual y peticiones
/// autenticadas. La sesión se guarda en el dispositivo para poder trabajar
/// sin conexión.
class AuthService extends ChangeNotifier {
  /// [dbFor] da la base local de cada negocio. En la app es un archivo por
  /// negocio y además se publica como [DatabaseHelper.instance]; las pruebas
  /// pasan la suya.
  AuthService({SessionStore? store, ApiClient? api, DatabaseHelper Function(int businessId)? dbFor})
      : store = store ?? PrefsSessionStore(),
        api = api ?? ApiClient(),
        _dbFor = dbFor;

  /// Instancia usada por la app. Las pruebas crean las suyas.
  static AuthService instance = AuthService();

  final SessionStore store;
  final ApiClient api;
  final DatabaseHelper Function(int businessId)? _dbFor;

  Session? _session;
  Session? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get isAdmin => _session?.user.isAdmin ?? false;

  DatabaseHelper? _db;

  /// Base local del negocio actual.
  DatabaseHelper get db => _db ?? DatabaseHelper.instance;

  /// Se activa cuando el servidor rechaza la sesión (hay que volver al login).
  bool sessionExpired = false;

  Future<void> load() async {
    _session = await store.load();
    if (_session != null) await _useBusiness(_session!.businessId);
    notifyListeners();
  }

  /// Abre la base local del negocio (adoptando los datos de antes si toca).
  Future<void> _useBusiness(int businessId) async {
    if (_dbFor != null) {
      _db = _dbFor(businessId);
      return;
    }
    final helper = DatabaseHelper.forBusiness(businessId);
    final legacyOwner = await store.localBusinessId();
    // La base única de antes pertenece al negocio con el que se usaba (o, si
    // nunca se inició sesión, al primero en el que se entra).
    if (legacyOwner == null || legacyOwner == businessId) {
      await DatabaseHelper.adoptLegacy(helper);
    }
    if (!identical(DatabaseHelper.instance, helper)) {
      await DatabaseHelper.instance.close();
    }
    DatabaseHelper.instance = helper;
    _db = helper;
  }

  /// Comprueba el servidor; devuelve true si aún no tiene administrador.
  Future<bool> needsSetup(String serverUrl) async {
    final r = await api.send(ApiClient.normalizeUrl(serverUrl), 'GET', '/status');
    if (r['ok'] != true) {
      throw ApiException(0, 'Esa dirección no corresponde a la API de facturas.');
    }
    return r['needs_setup'] == true;
  }

  Future<void> login(String serverUrl, String username, String password) async {
    final url = ApiClient.normalizeUrl(serverUrl);
    final r = await api.send(url, 'POST', '/auth/login',
        body: {'username': username.trim(), 'password': password});
    await _start(url, r);
  }

  /// Primera vez: crea el primer negocio y la cuenta de superadministrador.
  Future<void> setup(String serverUrl, String businessName, String name,
      String username, String password) async {
    final url = ApiClient.normalizeUrl(serverUrl);
    final r = await api.send(url, 'POST', '/auth/setup', body: {
      'business_name': businessName.trim(),
      'name': name.trim(),
      'username': username.trim(),
      'password': password,
    });
    await _start(url, r);
  }

  Future<void> _start(String url, Map<String, Object?> response) async {
    final previous = await store.load();
    var session = Session.fromApi(url, response);
    // Otro servidor: los puntos de sincronización anteriores no sirven.
    if (previous != null && previous.serverUrl != url) await store.clearCursors();
    session = session.copyWith(cursor: await store.cursorFor(session.businessId));
    await _useBusiness(session.businessId);
    await store.save(session);
    await store.setLastServerUrl(url);
    await store.setLocalBusinessId(session.businessId);
    _session = session;
    sessionExpired = false;
    notifyListeners();
  }

  /// Cambia al negocio indicado (requiere conexión). Los datos y cambios
  /// pendientes de cada negocio se conservan en su propia base local.
  Future<void> switchBusiness(int businessId) async {
    final current = _session;
    if (current == null) throw SessionExpiredException();
    if (current.businessId == businessId) return;
    final r = await request('POST', '/auth/switch', body: {'business_id': businessId});
    final next = Session.fromApi(current.serverUrl, r, cursor: await store.cursorFor(businessId));
    await _useBusiness(next.businessId);
    await store.save(next);
    _session = next;
    notifyListeners();
  }

  /// Cierra la sesión y borra los datos de todos los negocios del dispositivo
  /// (puede usar el móvil otra persona después).
  Future<void> logout() async {
    final ids = <int>{
      ...?_session?.businesses.map((b) => b.id),
      if (_session != null) _session!.businessId,
    };
    for (final id in ids) {
      final helper = _dbFor?.call(id) ?? DatabaseHelper.forBusiness(id);
      await helper.deleteFile();
    }
    if (_dbFor == null) {
      await DatabaseHelper(fileName: DatabaseHelper.legacyFileName).deleteFile();
      DatabaseHelper.instance = DatabaseHelper();
    }
    _db = null;
    await store.clear();
    await store.clearCursors();
    await store.setLocalBusinessId(null);
    _session = null;
    notifyListeners();
  }

  /// Guarda hasta dónde se sincronizó [businessId]. Si mientras tanto se
  /// cambió de negocio, solo se guarda para ese negocio.
  Future<void> updateCursor(int cursor, {int? businessId}) async {
    final s = _session;
    if (s == null) return;
    final id = businessId ?? s.businessId;
    await store.setCursorFor(id, cursor);
    if (id != s.businessId) return;
    _session = s.copyWith(cursor: cursor);
    await store.save(_session!);
  }

  /// Petición autenticada; renueva la sesión si ha caducado.
  Future<Map<String, Object?>> request(String method, String path,
      {Map<String, Object?>? body}) async {
    var s = _session;
    if (s == null) throw SessionExpiredException();
    if (DateTime.now().isAfter(s.accessExpiresAt)) {
      s = await _refresh(s);
    }
    try {
      return await api.send(s.serverUrl, method, path, body: body, token: s.accessToken);
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      s = await _refresh(s);
      return api.send(s.serverUrl, method, path, body: body, token: s.accessToken);
    }
  }

  Future<Session> _refresh(Session s) async {
    try {
      final r = await api.send(s.serverUrl, 'POST', '/auth/refresh',
          body: {'refresh_token': s.refreshToken});
      final fresh = Session.fromApi(s.serverUrl, r, cursor: _session?.cursor ?? s.cursor);
      await store.save(fresh);
      _session = fresh;
      notifyListeners();
      return fresh;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        sessionExpired = true;
        notifyListeners();
        throw SessionExpiredException();
      }
      rethrow;
    }
  }

  /// Cambia la propia contraseña (cierra la sesión en otros dispositivos).
  Future<void> changePassword(String current, String newPassword) async {
    final r = await request('POST', '/auth/password',
        body: {'current_password': current, 'new_password': newPassword});
    final fresh = Session.fromApi(_session!.serverUrl, r, cursor: _session!.cursor);
    await store.save(fresh);
    _session = fresh;
    notifyListeners();
  }
}
