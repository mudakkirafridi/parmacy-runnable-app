import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Each workspace and its upload queue commit together in one SQLite row.
class LocalWorkspace {
  final SharedPreferences prefs;
  Database? _db;
  LocalWorkspace(this.prefs);
  Future<void> open() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _db = await openDatabase(
        '${await getDatabasesPath()}/pharmacy_workspace.db',
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE workspaces (scope TEXT PRIMARY KEY, body TEXT NOT NULL)',
        ),
      );
    }
  }

  Future<String?> read(String scope) async {
    if (_db != null) {
      final rows = await _db!.query(
        'workspaces',
        columns: ['body'],
        where: 'scope = ?',
        whereArgs: [scope],
      );
      if (rows.isNotEmpty) return rows.first['body'] as String;
    }
    return prefs.getString(scope); // Upgrade migration; never discard old data.
  }

  Future<void> write(String scope, Map<String, dynamic> value) async {
    final body = jsonEncode(value);
    if (_db != null) {
      await _db!.insert('workspaces', {
        'scope': scope,
        'body': body,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await prefs.setString(scope, body);
    }
  }
}
