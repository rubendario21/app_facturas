import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Base de datos local: copia de trabajo de los datos del servidor más la cola
/// de cambios pendientes de enviar (outbox), para poder trabajar sin conexión.
class DatabaseHelper {
  DatabaseHelper({this.path, this.fileName = legacyFileName});

  /// Base local de un negocio: cada negocio tiene la suya, así que cambiar de
  /// negocio no borra nada y cada uno funciona sin conexión.
  factory DatabaseHelper.forBusiness(int businessId) =>
      DatabaseHelper(fileName: 'facturas_b$businessId.db');

  /// Instancia usada por la app (la del negocio actual). Las pruebas pueden
  /// sustituirla.
  static DatabaseHelper instance = DatabaseHelper();

  /// Archivo único de antes de los varios negocios.
  static const legacyFileName = 'facturas.db';

  /// Ruta completa del archivo; si es null se usa [fileName] en la carpeta
  /// de bases de datos de la app.
  final String? path;
  final String fileName;

  static const version = 4;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<String> resolvedPath() async => path ?? join(await getDatabasesPath(), fileName);

  /// Borra el archivo de la base (al cerrar sesión).
  Future<void> deleteFile() async {
    await close();
    await deleteDatabase(await resolvedPath());
  }

  /// Si existe la base única de antes y este negocio aún no tiene la suya,
  /// la adopta (se renombra) para no perder esos datos.
  static Future<void> adoptLegacy(DatabaseHelper target) async {
    if (target.path != null) return;
    final dir = await getDatabasesPath();
    final legacy = File(join(dir, legacyFileName));
    final dest = File(join(dir, target.fileName));
    if (await legacy.exists() && !await dest.exists()) {
      await instance.close();
      await legacy.rename(dest.path);
    }
  }

  Future<Database> _open() async {
    return openDatabase(
      await resolvedPath(),
      version: version,
      // Las claves foráneas se activan al abrir, DESPUÉS de las migraciones:
      // reconstruir una tabla con ellas activas borraría en cascada sus hijos.
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createIssuer(db);
    await _createInvoices(db, 'invoices');
    await _createItems(db);
    await _createPayments(db);
    await _addPaymentSyncColumns(db);
    await _createOutbox(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE issuer ADD COLUMN logo BLOB');
    }
    if (oldVersion < 3) {
      await _createPayments(db);
      // Las facturas ya marcadas como pagadas reciben un pago por el total,
      // para que su historial cuadre con el nuevo sistema de abonos.
      await db.execute('''
        INSERT INTO payments(invoice_id, amount, date, method, note, created_at)
        SELECT i.id,
               ROUND(COALESCE((SELECT SUM(quantity * unit_price)
                               FROM invoice_items WHERE invoice_id = i.id), 0)
                     * (1 + i.tax_rate / 100), 2),
               COALESCE(i.paid_date, i.issue_date),
               '', 'Pago registrado antes de los abonos', datetime('now')
        FROM invoices i WHERE i.paid = 1''');
    }
    if (oldVersion < 4) {
      // Sincronización: identificadores UUID, número opcional (borradores) y
      // cola de cambios. SQLite no permite quitar NOT NULL/UNIQUE con ALTER,
      // así que la tabla de facturas se reconstruye conservando los ids.
      await _createInvoices(db, 'invoices_v4');
      await db.execute('''
        INSERT INTO invoices_v4 (id, uuid, number, issue_date, due_date, client_name,
          client_tax_id, client_address, client_email, tax_rate, notes, paid,
          paid_date, created_at)
        SELECT id, $_uuidSql, number, issue_date, due_date, client_name,
          client_tax_id, client_address, client_email, tax_rate, notes, paid,
          paid_date, created_at
        FROM invoices''');
      await db.execute('DROP TABLE invoices');
      await db.execute('ALTER TABLE invoices_v4 RENAME TO invoices');
      await _addPaymentSyncColumns(db);
      await db.execute('UPDATE payments SET uuid = $_uuidSql');
      await _createOutbox(db);
      // El login local se sustituye por el del servidor.
      await db.execute('DROP TABLE IF EXISTS users');
    }
  }

  /// UUID v4 aleatorio generado por SQLite (para migrar registros existentes).
  static const _uuidSql = '''
    lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6)))''';

  Future<void> _createIssuer(Database db) => db.execute('''
      CREATE TABLE issuer(
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT,
        tax_id TEXT,
        address TEXT,
        city TEXT,
        phone TEXT,
        email TEXT,
        bank_account TEXT,
        invoice_prefix TEXT,
        next_number INTEGER,
        default_tax_rate REAL,
        currency TEXT,
        logo BLOB
      )''');

  /// server_rev: versión del servidor (null = nunca sincronizada).
  Future<void> _createInvoices(Database db, String table) => db.execute('''
      CREATE TABLE $table(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        number TEXT,
        issue_date TEXT NOT NULL,
        due_date TEXT,
        client_name TEXT NOT NULL,
        client_tax_id TEXT,
        client_address TEXT,
        client_email TEXT,
        tax_rate REAL NOT NULL,
        notes TEXT,
        paid INTEGER NOT NULL DEFAULT 0,
        paid_date TEXT,
        created_at TEXT NOT NULL,
        server_rev INTEGER
      )''');

  Future<void> _createItems(Database db) => db.execute('''
      CREATE TABLE invoice_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
        description TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        position INTEGER NOT NULL
      )''');

  Future<void> _createPayments(Database db) => db.execute('''
      CREATE TABLE payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        method TEXT,
        note TEXT,
        created_at TEXT NOT NULL
      )''');

  Future<void> _addPaymentSyncColumns(Database db) async {
    await db.execute('ALTER TABLE payments ADD COLUMN uuid TEXT');
    await db.execute('ALTER TABLE payments ADD COLUMN receipt_number TEXT');
    await db.execute('ALTER TABLE payments ADD COLUMN server_rev INTEGER');
    await db.execute('CREATE UNIQUE INDEX ix_payments_uuid ON payments(uuid)');
  }

  /// Cambios hechos en el dispositivo pendientes de enviar, en orden.
  Future<void> _createOutbox(Database db) => db.execute('''
      CREATE TABLE outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        entity_uuid TEXT NOT NULL,
        invoice_uuid TEXT,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''');
}
