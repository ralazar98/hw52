import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_chat_flutter/models/message.dart';
import 'package:ai_chat_flutter/services/database_service.dart';

import 'support/memory_auth_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  for (final oldVersion in [0, 1, 2]) {
    test(
      'database v$oldVersion: migration, persistence, replacement and reset',
      () async {
        final directory = await Directory.systemTemp.createTemp('aichat-auth-');
        final path = p.join(directory.path, 'chat_cache.db');
        if (oldVersion > 0) {
          final seed = await databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: oldVersion,
              onCreate: (db, _) async {
                await db.execute('''CREATE TABLE messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL,
              is_user INTEGER NOT NULL, timestamp TEXT NOT NULL,
              model_id TEXT, tokens INTEGER, cost REAL)''');
                await db.insert('messages', {
                  'content': 'До миграции',
                  'is_user': 1,
                  'timestamp': DateTime(2026).toIso8601String(),
                });
                if (oldVersion == 2) {
                  // Та же схема auth, которую успел создать Cline.
                  await db.execute(
                    '''CREATE TABLE auth (
                id INTEGER PRIMARY KEY AUTOINCREMENT, api_key TEXT NOT NULL,
                provider TEXT NOT NULL, base_url TEXT NOT NULL, pin_hash TEXT NOT NULL,
                salt TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
                  );
                }
              },
            ),
          );
          await seed.close();
        }
        var store = DatabaseService.forTesting(
          factory: databaseFactoryFfi,
          path: path,
        );
        try {
          // Параллельные обращения должны использовать одно открытие БД.
          final opened = await Future.wait([store.database, store.database]);
          expect(identical(opened[0], opened[1]), isTrue);
          expect(await opened[0].getVersion(), 2);
          if (oldVersion > 0) {
            expect((await store.getMessages()).single.content, 'До миграции');
          }
          await store.saveMessage(
            ChatMessage(content: 'После миграции', isUser: true),
          );
          await store.saveAuth(savedAuth());
          await store.close();
          store = DatabaseService.forTesting(
            factory: databaseFactoryFfi,
            path: path,
          );
          expect((await store.readAuth())!.apiKey, 'sk-or-v1-test');
          await store.saveAuth(savedAuth(key: 'sk-or-vis-new', pin: '5678'));
          final db = await store.database;
          expect((await db.query('auth')).length, 1);
          expect((await store.readAuth())!.provider, 'vsegpt');
          final beforeReset = (await store.getMessages()).length;
          await store.deleteAuth();
          expect(await store.readAuth(), isNull);
          expect((await store.getMessages()).length, beforeReset);
          expect(beforeReset, oldVersion > 0 ? 2 : 1);
        } finally {
          await store.close();
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
