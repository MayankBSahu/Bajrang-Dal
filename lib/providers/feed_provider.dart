import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/post.dart';
import '../db/database_helper.dart';

class FeedProvider extends ChangeNotifier {
  List<Post> _posts = [];
  List<Post> get posts => _posts;

  Future<void> loadPosts() async {
    _posts = await DatabaseHelper.instance.getAllPosts();
    notifyListeners();
  }

  Future<Post> createPost(String content, String authorId, String authorName) async {
    final post = Post(
      postId: const Uuid().v4(),
      authorId: authorId,
      authorName: authorName,
      content: content,
      createdAt: DateTime.now(),
      hopCount: 0,
      synced: false,
    );
    await DatabaseHelper.instance.insertPost(post);
    _posts.insert(0, post);
    notifyListeners();
    return post;
  }

  // Called when gossip delivers posts from another peer
  Future<void> receivePosts(List<Post> incoming) async {
    for (final post in incoming) {
      await DatabaseHelper.instance.insertPost(post); // ignore on duplicate
    }
    await loadPosts();
  }
}