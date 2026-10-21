import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/issuer.dart';
import 'database_helper.dart';
import 'outbox.dart';

class IssuerRepository {
  IssuerRepository([this._helper]);

  final DatabaseHelper? _helper;

  /// Clave fija de la cola para los cambios del emisor (hay uno por negocio).
  static const outboxKey = 'issuer';

  Future<Database> get _db => (_helper ?? DatabaseHelper.instance).database;

  Future<Issuer> get() async {
    final db = await _db;
    final rows = await db.query('issuer', where: 'id = 1');
    return rows.isEmpty ? const Issuer() : Issuer.fromMap(rows.first);
  }

  /// Guarda en local y encola para el servidor solo los campos modificados.
  Future<void> save(Issuer issuer) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('issuer', where: 'id = 1');
      final before = rows.isEmpty ? null : Issuer.fromMap(rows.first);
      await txn.insert('issuer', issuer.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

      final now = _toServer(issuer);
      final old = before == null ? null : _toServer(before);
      final changed = <String, Object?>{
        for (final e in now.entries)
          if (old == null || old[e.key] != e.value) e.key: e.value,
      };
      if (before == null || !listEquals(before.logo, issuer.logo)) {
        changed['logo'] =
            issuer.logo == null ? null : base64Encode(issuer.logo!);
      }
      if (changed.isNotEmpty) {
        await Outbox.add(txn, 'issuer_update', outboxKey, changed);
      }
    });
    Outbox.notifyChanged();
  }

  /// Encola todos los datos del emisor local (al subir datos anteriores a la
  /// sincronización). El contador de números no se envía: el servidor lo
  /// calcula a partir de los números de las facturas subidas.
  Future<void> enqueueAll() async {
    final db = await _db;
    final rows = await db.query('issuer', where: 'id = 1');
    if (rows.isEmpty) return;
    final issuer = Issuer.fromMap(rows.first);
    await Outbox.add(db, 'issuer_update', outboxKey, {
      ..._toServer(issuer)..remove('next_invoice_number'),
      'logo': issuer.logo == null ? null : base64Encode(issuer.logo!),
    });
    Outbox.notifyChanged();
  }

  /// Aplica el emisor recibido del servidor, salvo que haya cambios locales
  /// del emisor sin enviar.
  static Future<void> applyServerIssuer(
      DatabaseExecutor db, Map<String, Object?> j) async {
    if (await Outbox.hasPending(db, outboxKey)) return;
    final logo = j['logo'] as String?;
    await db.insert(
      'issuer',
      Issuer(
        name: j['name'] as String? ?? '',
        taxId: j['tax_id'] as String? ?? '',
        address: j['address'] as String? ?? '',
        city: j['city'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        email: j['email'] as String? ?? '',
        bankAccount: j['bank_account'] as String? ?? '',
        invoicePrefix: j['invoice_prefix'] as String? ?? 'F-',
        nextNumber: (j['next_invoice_number'] as num?)?.toInt() ?? 1,
        defaultTaxRate: (j['default_tax_rate'] as num?)?.toDouble() ?? 19,
        currency: j['currency'] as String? ?? r'$',
        logo: logo == null ? null : base64Decode(logo),
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Map<String, Object?> _toServer(Issuer i) => {
        'name': i.name,
        'tax_id': i.taxId,
        'address': i.address,
        'city': i.city,
        'phone': i.phone,
        'email': i.email,
        'bank_account': i.bankAccount,
        'invoice_prefix': i.invoicePrefix,
        'next_invoice_number': i.nextNumber,
        'default_tax_rate': i.defaultTaxRate,
        'currency': i.currency,
      };
}
