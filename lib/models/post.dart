class Post {
  final String postId;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime createdAt;
  final int hopCount;       // how many peers this has passed through
  bool synced;              // has this been sent to at least one peer

  Post({
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.hopCount = 0,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
    'post_id': postId,
    'author_id': authorId,
    'author_name': authorName,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'hop_count': hopCount,
    'synced': synced ? 1 : 0,
  };

  factory Post.fromMap(Map<String, dynamic> m) => Post(
    postId: m['post_id'],
    authorId: m['author_id'],
    authorName: m['author_name'],
    content: m['content'],
    createdAt: DateTime.parse(m['created_at']),
    hopCount: m['hop_count'] ?? 0,
    synced: m['synced'] == 1,
  );

  // Used during gossip sync
  Map<String, dynamic> toJson() => toMap();
  factory Post.fromJson(Map<String, dynamic> j) => Post.fromMap(j);
}