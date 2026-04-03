import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../channels/p2p_channel.dart';
import '../models/post.dart';
import '../providers/feed_provider.dart';
import '../providers/identity_provider.dart';
import '../providers/peer_provider.dart';
import '../providers/mesh_debug_provider.dart';

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
            onPressed: () async {
              final identity = context.read<IdentityProvider>().identity;
              final text = controller.text.trim();
              if (identity != null && text.isNotEmpty) {
                await context.read<FeedProvider>().createPost(
                  text,
                  identity.peerId,
                  identity.displayName,
                );
                // Always try native push when on Android; Kotlin checks the gossip socket.
                // Previously we gated on p2pConnected — that often stayed false when P2P
                // callbacks ran off the Android main thread.
                if (context.mounted &&
                    !kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android) {
                  try {
                    await P2PChannel.pushGossipSync();
                  } on PlatformException catch (e) {
                    if (context.mounted &&
                        e.code == 'NO_SOCKET' &&
                        ScaffoldMessenger.maybeOf(context) != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e.message ??
                                'Connected peer data link is down. Use Nearby to connect, then post again.',
                          ),
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    } else {
                      debugPrint('pushGossipSync: ${e.code} ${e.message}');
                    }
                  }
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
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
    final p2pConnected = context.watch<PeerProvider>().p2pConnected;
    final debug = context.watch<MeshDebugProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('MeshSocial'), centerTitle: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPostDialog(context),
        child: const Icon(Icons.edit),
      ),
      body: Column(
        children: [
          if (debug.lastError != null || debug.lastAppliedAt != null)
            Material(
              color: Colors.black.withValues(alpha: 0.03),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mesh debug: ${p2pConnected ? 'link up' : 'link down'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (debug.lastPushAt != null)
                      Text(
                        'Last push: ${debug.lastPushedPostCount} posts @ '
                        '${debug.lastPushAt!.toLocal().toIso8601String().substring(11, 19)}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    if (debug.lastAppliedAt != null)
                      Text(
                        'Last received/apply: ${debug.lastAppliedCount} @ '
                        '${debug.lastAppliedAt!.toLocal().toIso8601String().substring(11, 19)}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    if (debug.lastError != null)
                      Text(
                        'Error: ${debug.lastError}',
                        style: const TextStyle(fontSize: 12.5, color: Colors.red),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: posts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (p2pConnected) ...[
                            Icon(
                              Icons.link,
                              size: 40,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            p2pConnected
                                ? 'No posts yet.\n\nYour mesh link is up — tap + to write a post. '
                                    'New posts are sent to your peer over Wi‑Fi Direct.'
                                : 'No posts yet.\n\nTap + to create a post. To sync with another phone, '
                                    'open the Nearby tab and connect to a peer first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              height: 1.35,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: posts.length,
                    separatorBuilder: (context, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _PostTile(post: posts[i]),
                  ),
          ),
        ],
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
      leading: CircleAvatar(
        child: Text(
          post.authorName.isNotEmpty
              ? post.authorName[0].toUpperCase()
              : '?',
        ),
      ),
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