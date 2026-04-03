import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/post.dart';
import '../models/peer.dart';
import '../models/identity.dart';

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
      version: 2,
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
      CREATE TABLE posts (
        post_id     TEXT PRIMARY KEY,
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
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE peers ADD COLUMN transport TEXT DEFAULT 'wifiDirect'",
      );
    }
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
}
