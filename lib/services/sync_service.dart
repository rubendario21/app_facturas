import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database_helper.dart';
import '../data/invoice_repository.dart';
import '../data/issuer_repository.dart';
import '../data/outbox.dart';
import 'api_client.dart';
import 'auth_service.dart';

enum SyncStatus { idle, syncing, offline, error, sessionExpired }

/// Sincroniza la base local con el servidor: envía la cola de cambios del
/// dispositivo y descarga los de los demás.
class SyncService extends ChangeNotifier {
  SyncService({AuthService? auth, DatabaseHelper? db})
      : _auth = auth,
        _db = db;

  static SyncService instance = SyncService();

  final AuthService? _auth;
  final DatabaseHelper? _db;

  AuthService get auth => _auth ?? AuthService.instance;
  /// Base local del negocio actual (cambia al cambiar de negocio).
  DatabaseHelper get db => _db ?? auth.db;

  static const _batchSize = 100;
  static const _interval = Duration(seconds: 60);

  SyncStatus status = SyncStatus.idle;
  String? lastError;
  DateTime? lastSync;
  int pending = 0;

  /// Mensajes de cambios que el servidor no aceptó (para avisar al usuario).
  final rejections = <String>[];

  /// Aumenta cada vez que llegan datos nuevos (las pantallas recargan).
  final dataVersion = ValueNotifier<int>(0);

  Timer? _timer;
  Timer? _debounce;
  bool _running = false;
  bool _again = false;

  /// Empieza a sincronizar en segundo plano mientras la app está abierta.
  void start() {
    stop();
    Outbox.changes.addListener(_onLocalChange);
    _timer = Timer.periodic(_interval, (_) => sync());
    sync();
  }

  void stop() {
    Outbox.changes.removeListener(_onLocalChange);
    _timer?.cancel();
    _debounce?.cancel();
  }

  /// Espera a que termine la sincronización en curso (antes de cambiar de
  /// negocio o cerrar sesión).
  Future<void> idle() async {
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _onLocalChange() {
    _refreshPending();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), sync);
  }

  Future<void> _refreshPending() async {
    pending = await Outbox.count(await db.database);
    notifyListeners();
  }

  List<String> takeRejections() {
    final list = List<String>.of(rejections);
    rejections.clear();
    return list;
  }

  /// Sincroniza ahora. Si ya hay una sincronización en marcha, se repite al
  /// terminar para incluir los cambios recientes.
  Future<void> sync() async {
    if (!auth.isLoggedIn) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      do {
        _again = false;
        final more = await _round();
        if (more) _again = true;
      } while (_again);
      status = SyncStatus.idle;
      lastError = null;
      lastSync = DateTime.now();
    } on NetworkException catch (e) {
      status = SyncStatus.offline;
      lastError = e.message;
    } on SessionExpiredException catch (e) {
      status = SyncStatus.sessionExpired;
      lastError = e.toString();
    } on ApiException catch (e) {
      status = SyncStatus.error;
      lastError = e.message;
    } catch (e) {
      status = SyncStatus.error;
      lastError = 'Error al sincronizar: $e';
    } finally {
      _running = false;
      pending = await Outbox.count(await db.database);
      notifyListeners();
    }
  }

  /// Una ronda: envía hasta [_batchSize] cambios y aplica la respuesta.
  /// Devuelve true si quedan más cambios por enviar.
  Future<bool> _round() async {
    // Negocio y base de esta ronda, aunque se cambie de negocio a mitad.
    final businessId = auth.session!.businessId;
    final database = await db.database;
    final ops = await Outbox.pending(database, limit: _batchSize);
    final response = await auth.request('POST', '/sync', body: {
      'cursor': auth.session!.cursor,
      'changes': [for (final op in ops) op.toJson()],
    });
    final results = (response['results'] as List).cast<Map<String, Object?>>();
    var changed = false;

    await database.transaction((txn) async {
      for (var i = 0; i < ops.length && i < results.length; i++) {
        final result = results[i];
        await Outbox.remove(txn, ops[i].id);
        if (result['status'] == 'rejected') {
          rejections.add(
              result['message'] as String? ?? 'El servidor rechazó un cambio.');
          // Un pago rechazado nunca llegó al servidor: se quita del móvil.
          if (ops[i].type == 'payment_add' && result['payment'] == null) {
            await _dropLocalPayment(txn, ops[i].entityUuid);
          }
          // Factura rechazada al crearse: se quita (no existe en el servidor).
          if (ops[i].type == 'invoice_upsert' && result['invoice'] == null) {
            await Outbox.removeForInvoice(txn, ops[i].entityUuid);
            await txn.delete('invoices',
                where: 'uuid = ? AND server_rev IS NULL',
                whereArgs: [ops[i].entityUuid]);
          }
        }
        if (result['invoice'] is Map) {
          await InvoiceRepository.applyServerInvoice(
              txn, result['invoice'] as Map<String, Object?>);
        }
        if (result['payment'] is Map) {
          await InvoiceRepository.applyServerPayment(
              txn, result['payment'] as Map<String, Object?>);
        }
        if (result['issuer'] is Map) {
          await IssuerRepository.applyServerIssuer(
              txn, result['issuer'] as Map<String, Object?>);
        }
        changed = true;
      }

      if (response['reset'] == true) {
        // El servidor no reconoce nuestro punto de sincronización: se
        // descarga todo de nuevo (lo pendiente de enviar se conserva).
        await txn.delete('payments', where: 'server_rev IS NOT NULL');
        await txn.delete('invoices', where: 'server_rev IS NOT NULL');
      }
      for (final j
          in (response['invoices'] as List).cast<Map<String, Object?>>()) {
        await InvoiceRepository.applyServerInvoice(txn, j);
        changed = true;
      }
      for (final j
          in (response['payments'] as List).cast<Map<String, Object?>>()) {
        await InvoiceRepository.applyServerPayment(txn, j);
        changed = true;
      }
      if (response['issuer'] is Map) {
        await IssuerRepository.applyServerIssuer(
            txn, response['issuer'] as Map<String, Object?>);
        changed = true;
      }
    });

    await auth.updateCursor((response['cursor'] as num).toInt(), businessId: businessId);
    if (changed) dataVersion.value++;
    return ops.length == _batchSize;
  }

  Future<void> _dropLocalPayment(DatabaseExecutor txn, String uuid) async {
    final row =
        (await txn.query('payments', where: 'uuid = ?', whereArgs: [uuid]))
            .firstOrNull;
    if (row == null) return;
    await txn.delete('payments', where: 'id = ?', whereArgs: [row['id']]);
    await InvoiceRepository.syncPaidStatus(txn, row['invoice_id'] as int);
  }

  @override
  void dispose() {
    stop();
    dataVersion.dispose();
    super.dispose();
  }
}
