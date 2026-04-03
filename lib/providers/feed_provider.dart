import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/post.dart';
import '../db/database_helper.dart';

class FeedProvider extends ChangeNotifier {
  List<Post> _posts = [];
  List<Post> get posts => _posts;
  String _activeRoomId = 'general';
  String get activeRoomId => _activeRoomId;

  Future<void> loadPosts({String? roomId}) async {
    _activeRoomId = roomId ?? _activeRoomId;
    _posts = await DatabaseHelper.instance.getPostsForRoom(_activeRoomId);
    notifyListeners();
  }

  Future<Post> createPost(
    String content,
    String authorId,
    String authorName, {
    required String roomId,
    required String roomName,
  }) async {
    final post = Post(
      postId: const Uuid().v4(),
      roomId: roomId,
      roomName: roomName,
      authorId: authorId,
      authorName: authorName,
      content: content,
      createdAt: DateTime.now(),
      hopCount: 0,
      synced: false,
    );
    await DatabaseHelper.instance.insertPost(post);
    if (_activeRoomId == roomId) {
      _posts.insert(0, post);
      notifyListeners();
    }
    return post;
  }

  // Called when gossip delivers posts from another peer
  Future<void> receivePosts(List<Post> incoming) async {
    for (final post in incoming) {
      await DatabaseHelper.instance.insertPost(post); // ignore on duplicate
    }
    await loadPosts();
  }

  /// Serialized rows for P2P sync (same shape as DB / [Post.toMap]).
  Future<List<Map<String, dynamic>>> exportPostsForSync() async {
    final posts = await DatabaseHelper.instance.getAllPosts();
    return posts.map((p) => p.toMap()).toList();
  }

  /// Returns only the post IDs for HELLO handshake (Delta Sync).
  Future<List<String>> exportPostIdsForSync() async {
    return await DatabaseHelper.instance.getPostIds();
  }

  /// Returns serialized rows for specific requested post IDs.
  Future<List<Map<String, dynamic>>> exportSpecificPosts(List<String> requestedIds) async {
    final requestedSet = requestedIds.toSet();
    final posts = await DatabaseHelper.instance.getAllPosts();
    return posts.where((p) => requestedSet.contains(p.postId)).map((p) => p.toMap()).toList();
  }

  Future<void> markOwnPostsSynced(String authorId) async {
    await DatabaseHelper.instance.markAuthorPostsSynced(authorId);
    await loadPosts(roomId: _activeRoomId);
  }

  /// Inserts merged rows produced by native [GossipEngine] (snake_case maps).
  Future<void> applyPostsFromGossip(List<dynamic> raw) async {
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final post = Post(
        postId: m['post_id'] as String? ?? '',
        roomId: m['room_id'] as String? ?? 'general',
        roomName: m['room_name'] as String? ?? 'General',
        authorId: m['author_id'] as String? ?? '',
        authorName: m['author_name'] as String? ?? 'Unknown',
        content: m['content'] as String? ?? '',
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        hopCount: (m['hop_count'] as num?)?.toInt() ?? 0,
        synced: m['synced'] == 1 || m['synced'] == true,
      );
      if (post.postId.isEmpty) continue;
      await DatabaseHelper.instance.insertPost(post);
    }
    await loadPosts(roomId: _activeRoomId);
  }
}
