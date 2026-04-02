import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/identity_provider.dart';
import '../providers/feed_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _editName(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Display Name'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              context.read<IdentityProvider>().updateName(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityProvider>().identity;
    final myPosts = context.watch<FeedProvider>().posts
        .where((p) => p.authorId == identity?.peerId)
        .toList();

    if (identity == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              child: Text(identity.displayName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => _editName(context, identity.displayName),
              icon: const Icon(Icons.edit, size: 16),
              label: Text(identity.displayName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(identity.peerId,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          const Divider(height: 32),
          Text('My Posts (${myPosts.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...myPosts.map((p) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(p.content),
            ),
          )),
        ],
      ),
    );
  }
}