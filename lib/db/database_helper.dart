import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/post.dart';
import '../models/peer.dart';
import '../models/identity.dart';
import '../models/room.dart';
import '../models/shared_file.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _db;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB('meshsocial.db');
    return _db!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE identity (
        peer_id     TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        public_key  TEXT NOT NULL,
        created_at  TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE rooms (
        room_id     TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        is_locked   INTEGER DEFAULT 0,
        password    TEXT DEFAULT '',
        created_at  TEXT NOT NULL,
        joined_at   TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE shared_files (
        file_id      TEXT PRIMARY KEY,
        room_id      TEXT NOT NULL,
        room_name    TEXT NOT NULL,
        sender_id    TEXT NOT NULL,
        sender_name  TEXT NOT NULL,
        file_name    TEXT NOT NULL,
        local_path   TEXT NOT NULL,
        file_size    INTEGER DEFAULT 0,
        mime_type    TEXT DEFAULT 'application/octet-stream',
        created_at   TEXT NOT NULL,
        is_outgoing  INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE posts (
        post_id     TEXT PRIMARY KEY,
        room_id     TEXT NOT NULL,
        room_name   TEXT NOT NULL,
        author_id   TEXT NOT NULL,
        author_name TEXT NOT NULL,
        content     TEXT NOT NULL,
        created_at  TEXT NOT NULL,
        hop_count   INTEGER DEFAULT 0,
        synced      INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE peers (
        peer_id        TEXT PRIMARY KEY,
        display_name   TEXT NOT NULL,
        device_address TEXT NOT NULL,
        transport      TEXT DEFAULT 'wifiDirect',
        status         TEXT DEFAULT 'discovered',
        last_seen      TEXT NOT NULL
      )
    ''');

    await _ensureDefaultRoom(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE peers ADD COLUMN transport TEXT DEFAULT 'wifiDirect'",
      );
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS rooms (
          room_id     TEXT PRIMARY KEY,
          name        TEXT NOT NULL,
          is_locked   INTEGER DEFAULT 0,
          password    TEXT DEFAULT '',
          created_at  TEXT NOT NULL,
          joined_at   TEXT NOT NULL
        )
      ''');
      await db.execute(
        "ALTER TABLE posts ADD COLUMN room_id TEXT NOT NULL DEFAULT 'general'",
      );
      await db.execute(
        "ALTER TABLE posts ADD COLUMN room_name TEXT NOT NULL DEFAULT 'General'",
      );
      await _ensureDefaultRoom(db);
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS shared_files (
          file_id      TEXT PRIMARY KEY,
          room_id      TEXT NOT NULL,
          room_name    TEXT NOT NULL,
          sender_id    TEXT NOT NULL,
          sender_name  TEXT NOT NULL,
          file_name    TEXT NOT NULL,
          local_path   TEXT NOT NULL,
          file_size    INTEGER DEFAULT 0,
          mime_type    TEXT DEFAULT 'application/octet-stream',
          created_at   TEXT NOT NULL,
          is_outgoing  INTEGER DEFAULT 0
        )
      ''');
    }
  }

  Future<void> _ensureDefaultRoom(Database db) async {
    final now = DateTime.now();
    await db.insert(
      'rooms',
      Room(
        roomId: 'general',
        name: 'General',
        isLocked: false,
        password: '',
        createdAt: now,
        joinedAt: now,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // --- Identity ---
  Future<void> saveIdentity(Identity identity) async {
    final db = await database;
    await db.insert('identity', identity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Identity?> getIdentity() async {
    final db = await database;
    final rows = await db.query('identity', limit: 1);
    if (rows.isEmpty) return null;
    return Identity.fromMap(rows.first);
  }

  // --- Posts ---
  Future<void> insertPost(Post post) async {
    final db = await database;
    await db.insert('posts', post.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore); // ignore = no overwrite on gossip re-delivery
  }

  Future<List<Post>> getAllPosts() async {
    final db = await database;
    final rows = await db.query('posts', orderBy: 'created_at DESC');
    return rows.map(Post.fromMap).toList();
  }

  Future<List<Post>> getPostsForRoom(String roomId) async {
    final db = await database;
    final rows = await db.query(
      'posts',
      where: 'room_id = ?',
      whereArgs: [roomId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Post.fromMap).toList();
  }

  // --- Shared Files ---
  Future<void> insertSharedFile(SharedFile file) async {
    final db = await database;
    await db.insert(
      'shared_files',
      file.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<SharedFile>> getFilesForRoom(String roomId) async {
    final db = await database;
    final rows = await db.query(
      'shared_files',
      where: 'room_id = ?',
      whereArgs: [roomId],
      orderBy: 'created_at DESC',
    );
    return rows.map(SharedFile.fromMap).toList();
  }

  Future<List<String>> getPostIds() async {
    final db = await database;
    final rows = await db.query('posts', columns: ['post_id']);
    return rows.map((r) => r['post_id'] as String).toList();
  }

  Future<void> markSynced(String postId) async {
    final db = await database;
    await db.update('posts', {'synced': 1},
        where: 'post_id = ?', whereArgs: [postId]);
  }

  Future<void> markAuthorPostsSynced(String authorId) async {
    final db = await database;
    await db.update('posts', {'synced': 1},
        where: 'author_id = ?', whereArgs: [authorId]);
  }

  // --- Peers ---
  Future<void> upsertPeer(Peer peer) async {
    final db = await database;
    await db.insert('peers', peer.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Peer>> getKnownPeers() async {
    final db = await database;
    final rows = await db.query('peers', orderBy: 'last_seen DESC');
    return rows.map(Peer.fromMap).toList();
  }

  // --- Rooms ---
  Future<void> upsertRoom(Room room) async {
    final db = await database;
    await db.insert(
      'rooms',
      room.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Room?> getRoom(String roomId) async {
    final db = await database;
    final rows = await db.query(
      'rooms',
      where: 'room_id = ?',
      whereArgs: [roomId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Room.fromMap(rows.first);
  }

  Future<List<Room>> getRooms() async {
    final db = await database;
    final rows = await db.query(
      'rooms',
      orderBy: 'joined_at DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(Room.fromMap).toList();
  }
}
