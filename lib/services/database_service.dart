// Импорт платформо-зависимых функций
import 'dart:io' show Platform;

// Импорт утилит для работы с путями
import 'package:path/path.dart';
// Импорт основного пакета для работы с SQLite
import 'package:sqflite/sqflite.dart';
// Импорт основных классов Flutter
import 'package:flutter/foundation.dart';
// Импорт FFI реализации для desktop платформ
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Импорт модели сообщения
import '../models/message.dart';
// Импорт модели аутентификации
import '../models/auth_data.dart';

// Класс сервиса для работы с базой данных
class DatabaseService implements AuthStore {
  static const String tableMessages = 'messages';
  static const String tableAuth = 'auth';
  static const int dbVersion = 2;
  // Единственный экземпляр класса (Singleton)
  static final DatabaseService _instance = DatabaseService._internal();
  // Экземпляр базы данных
  Database? _database;
  Future<Database>? _opening;
  final DatabaseFactory? _factory;
  final String? _path;

  // Фабричный метод для получения экземпляра
  factory DatabaseService() {
    return _instance;
  }

  // Приватный конструктор для реализации Singleton
  DatabaseService._internal()
      : _factory = null,
        _path = null;

  DatabaseService.forTesting({
    required DatabaseFactory factory,
    required String path,
  })  : _factory = factory,
        _path = path;

  // Геттер для получения экземпляра базы данных
  Future<Database> get database async {
    if (_database != null) return _database!;
    _opening ??= _initDatabase();
    try {
      return _database = await _opening!;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  // Метод инициализации базы данных
  Future<Database> _initDatabase() async {
    // Инициализация FFI для desktop платформ
    if (_factory == null && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Получение пути к базе данных
    final factory = _factory ?? databaseFactory;
    final path = _path ??
        join(
          await factory.getDatabasesPath(),
          'chat_cache.db',
        ); // Имя файла базы данных

    // Открытие/создание базы данных
    return await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onCreate: (Database db, int version) async {
          // Создание таблицы messages при первом запуске
          await db.execute('''
          CREATE TABLE $tableMessages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            is_user INTEGER NOT NULL,
            timestamp TEXT NOT NULL,
            model_id TEXT,
            tokens INTEGER,
            cost REAL
          )
        ''');
          // Создание таблицы auth при первом запуске
          await db.execute('''
          CREATE TABLE $tableAuth (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            api_key TEXT NOT NULL,
            provider TEXT NOT NULL,
            base_url TEXT NOT NULL,
            pin_hash TEXT NOT NULL,
            salt TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            // Добавляем таблицу auth
            await db.execute('''
            CREATE TABLE $tableAuth (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              api_key TEXT NOT NULL,
              provider TEXT NOT NULL,
              base_url TEXT NOT NULL,
              pin_hash TEXT NOT NULL,
              salt TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          }
          // В будущих версиях добавлять новые миграции здесь
        },
      ),
    );
  }

  @override
  Future<AuthData?> readAuth() async {
    final db = await database;
    final rows = await db.query(tableAuth, orderBy: 'id DESC', limit: 1);
    return rows.isEmpty ? null : AuthData.fromMap(rows.single);
  }

  @override
  Future<void> saveAuth(AuthData auth) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(tableAuth);
      await transaction.insert(tableAuth, auth.toMap());
    });
  }

  @override
  Future<void> deleteAuth() async {
    final db = await database;
    await db.delete(tableAuth);
  }

  Future<void> close() async {
    final db = _database ?? await _opening;
    await db?.close();
    _database = null;
    _opening = null;
  }

  // Метод сохранения сообщения в базу данных
  Future<void> saveMessage(ChatMessage message) async {
    try {
      final db = await database;
      // Вставка данных в таблицу messages
      await db.insert(
        tableMessages,
        {
          'content': message.content, // Текст сообщения
          'is_user': message.isUser ? 1 : 0, // Преобразование bool в int
          'timestamp': message.timestamp.toIso8601String(), // Временная метка
          'model_id': message.modelId, // Идентификатор модели
          'tokens': message.tokens, // Количество токенов
          'cost': message.cost, // Стоимость запроса
        },
        conflictAlgorithm:
            ConflictAlgorithm.replace, // Стратегия при конфликтах
      );
    } catch (e) {
      debugPrint('Error saving message: $e'); // Логирование ошибок
    }
  }

  // Метод получения сообщений из базы данных
  Future<List<ChatMessage>> getMessages({int limit = 50}) async {
    try {
      final db = await database;
      // Запрос данных из таблицы messages
      final List<Map<String, dynamic>> maps = await db.query(
        tableMessages,
        orderBy: 'timestamp ASC', // Сортировка по времени
        limit: limit, // Ограничение количества записей
      );

      // Преобразование данных в объекты ChatMessage
      return List.generate(maps.length, (i) {
        return ChatMessage(
          content: maps[i]['content'] as String, // Текст сообщения
          isUser: maps[i]['is_user'] == 1, // Преобразование int в bool
          timestamp: DateTime.parse(
            maps[i]['timestamp'] as String,
          ), // Временная метка
          modelId: maps[i]['model_id'] as String?, // Идентификатор модели
          tokens: maps[i]['tokens'] as int?, // Количество токенов
          cost: maps[i]['cost'] as double?, // Стоимость запроса
        );
      });
    } catch (e) {
      debugPrint('Error getting messages: $e'); // Логирование ошибок
      return []; // Возврат пустого списка в случае ошибки
    }
  }

  // Метод очистки истории сообщений
  Future<void> clearHistory() async {
    try {
      final db = await database;
      await db.delete(tableMessages); // Удаление всех записей из таблицы
    } catch (e) {
      debugPrint('Error clearing history: $e'); // Логирование ошибок
    }
  }

  // Метод получения статистики по сообщениям
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final db = await database;

      // Получение общего количества сообщений
      final totalMessagesResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $tableMessages',
      );
      final totalMessages = Sqflite.firstIntValue(totalMessagesResult) ?? 0;

      // Получение общего количества токенов
      final totalTokensResult = await db.rawQuery(
        'SELECT SUM(tokens) as total FROM $tableMessages WHERE tokens IS NOT NULL',
      );
      final totalTokens = Sqflite.firstIntValue(totalTokensResult) ?? 0;

      // Получение статистики использования моделей
      final modelStats = await db.rawQuery('''
        SELECT 
          model_id,
          COUNT(*) as message_count,
          SUM(tokens) as total_tokens
        FROM messages 
        WHERE model_id IS NOT NULL 
        GROUP BY model_id
      ''');

      // Формирование данных по использованию моделей
      final modelUsage = <String, Map<String, int>>{};
      for (final stat in modelStats) {
        final modelId = stat['model_id'] as String;
        modelUsage[modelId] = {
          'count': stat['message_count'] as int, // Количество сообщений
          'tokens':
              stat['total_tokens'] as int? ?? 0, // Общее количество токенов
        };
      }

      return {
        'total_messages': totalMessages, // Общее количество сообщений
        'total_tokens': totalTokens, // Общее количество токенов
        'model_usage': modelUsage, // Статистика по моделям
      };
    } catch (e) {
      debugPrint('Error getting statistics: $e'); // Логирование ошибок
      return {'total_messages': 0, 'total_tokens': 0, 'model_usage': {}};
    }
  }
}
