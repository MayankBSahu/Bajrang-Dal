import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/identity_provider.dart';
import '../models/post.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  void _showPostDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Post'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: "What's on your mind?"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final identity = context.read<IdentityProvider>().identity;
              if (identity != null && controller.text.isNotEmpty) {
                context.read<FeedProvider>().createPost(
                  controller.text.trim(),
                  identity.peerId,
                  identity.displayName,
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posts = context.watch<FeedProvider>().posts;
    return Scaffold(
      appBar: AppBar(title: const Text('MeshSocial'), centerTitle: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPostDialog(context),
        child: const Icon(Icons.edit),
      ),
      body: posts.isEmpty
          ? const Center(child: Text('No posts yet.\nCreate one or connect to peers.',
              textAlign: TextAlign.center))
          : ListView.separated(
              itemCount: posts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) => _PostTile(post: posts[i]),
            ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final Post post;
  const _PostTile({required this.post});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Text(post.authorName[0].toUpperCase())),
      title: Text(post.authorName,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(post.content),
          const SizedBox(height: 4),
          Row(children: [
            Icon(post.synced ? Icons.cloud_done : Icons.schedule,
                size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text('${post.hopCount} hops',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ],
      ),
      isThreeLine: true,
    );
  }
}