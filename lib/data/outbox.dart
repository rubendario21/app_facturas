import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Un cambio local pendiente de enviar al servidor.
class OutboxOp {
  final int id;
  final String type;
  final String entityUuid;
  final Map<String, Object?> data;

  const OutboxOp(this.id, this.type, this.entityUuid, this.data);

  Map<String, Object?> toJson() => {'type': type, 'data': data};
}

/// Cola de cambios hechos en el dispositivo (funciona sin conexión).
class Outbox {
  /// Avisa de que hay algo nuevo en la cola (la sincronización lo escucha).
  static final changes = ValueNotifier<int>(0);

  static void notifyChanged() => changes.value++;

  /// Añade un cambio. Si ya hay un guardado pendiente de la misma factura,
  /// se actualiza en su sitio en lugar de enviar dos.
  static Future<void> add(
    DatabaseExecutor db,
    String type,
    String entityUuid,
    Map<String, Object?> data, {
    String? invoiceUuid,
  }) async {
    final payload = jsonEncode(data);
    if (type == 'invoice_upsert' || type == 'issuer_update') {
      final existing = await db.query('outbox',
          where: 'type = ? AND entity_uuid = ?',
          whereArgs: [type, entityUuid],
          orderBy: 'id DESC',
          limit: 1);
      if (existing.isNotEmpty) {
        final merged = type == 'issuer_update'
            ? {
                ...jsonDecode(existing.first['payload'] as String)
                    as Map<String, Object?>,
                ...data
              }
            : data;
        await db.update('outbox', {'payload': jsonEncode(merged)},
            where: 'id = ?', whereArgs: [existing.first['id']]);
        return;
      }
    }
    await db.insert('outbox', {
      'type': type,
      'entity_uuid': entityUuid,
      'invoice_uuid': invoiceUuid,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<OutboxOp>> pending(DatabaseExecutor db,
      {int limit = 100}) async {
    final rows = await db.query('outbox', orderBy: 'id', limit: limit);
    return [
      for (final r in rows)
        OutboxOp(
          r['id'] as int,
          r['type'] as String,
          r['entity_uuid'] as String,
          jsonDecode(r['payload'] as String) as Map<String, Object?>,
        ),
    ];
  }

  static Future<int> count(DatabaseExecutor db) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ??
      0;

  static Future<void> remove(DatabaseExecutor db, int id) =>
      db.delete('outbox', where: 'id = ?', whereArgs: [id]);

  /// ¿Hay cambios locales sin enviar de este registro?
  static Future<bool> hasPending(DatabaseExecutor db, String entityUuid,
      {List<String>? types}) async {
    final where = StringBuffer('entity_uuid = ?');
    final args = <Object?>[entityUuid];
    if (types != null) {
      where.write(' AND type IN (${List.filled(types.length, '?').join(',')})');
      args.addAll(types);
    }
    final rows = await db.query('outbox',
        where: where.toString(), whereArgs: args, limit: 1);
    return rows.isNotEmpty;
  }

  /// Quita de la cola todo lo relativo a una factura (y a sus pagos).
  static Future<void> removeForInvoice(
          DatabaseExecutor db, String invoiceUuid) =>
      db.delete('outbox',
          where: 'entity_uuid = ? OR invoice_uuid = ?',
          whereArgs: [invoiceUuid, invoiceUuid]);
}
