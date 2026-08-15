import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    return initialize();
  }

  Future<Database> initialize() async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      path.join(root, 'mhd_mikylov.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE active_trip (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            line_number TEXT NOT NULL,
            stop_index INTEGER NOT NULL,
            running INTEGER NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE gtfs_imports (
            source_url TEXT PRIMARY KEY,
            source_name TEXT NOT NULL,
            city TEXT NOT NULL,
            stop_count INTEGER NOT NULL,
            station_count INTEGER NOT NULL,
            route_count INTEGER NOT NULL,
            imported_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transit_stops (
            id TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            name TEXT NOT NULL,
            minutes INTEGER NOT NULL DEFAULT 0,
            latitude REAL,
            longitude REAL,
            location_type INTEGER NOT NULL DEFAULT 0,
            parent_station TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE transit_routes (
            id TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            short_name TEXT NOT NULL,
            long_name TEXT NOT NULL,
            color TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE route_stops (
            route_id TEXT NOT NULL,
            stop_id TEXT NOT NULL,
            stop_sequence INTEGER NOT NULL,
            PRIMARY KEY (route_id, stop_id, stop_sequence)
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_data (
            key TEXT PRIMARY KEY,
            json_value TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<void> saveActiveTrip({
    required String lineNumber,
    required int stopIndex,
    required bool running,
  }) async {
    final db = await database;
    await db.insert(
      'active_trip',
      {
        'id': 1,
        'line_number': lineNumber,
        'stop_index': stopIndex,
        'running': running ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> loadActiveTrip() async {
    final db = await database;
    final rows = await db.query('active_trip', where: 'id = 1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveSetting(String key, Object? value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<T?> loadSetting<T>(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['value']! as String) as T?;
  }

  Future<void> saveGtfsImport({
    required String sourceUrl,
    required String sourceName,
    required String city,
    required int stopCount,
    required int stationCount,
    required int routeCount,
  }) async {
    final db = await database;
    await db.insert(
      'gtfs_imports',
      {
        'source_url': sourceUrl,
        'source_name': sourceName,
        'city': city,
        'stop_count': stopCount,
        'station_count': stationCount,
        'route_count': routeCount,
        'imported_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> loadGtfsImports() async {
    final db = await database;
    return db.query('gtfs_imports', orderBy: 'imported_at DESC');
  }
}

final appDatabase = AppDatabase();
