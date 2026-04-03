import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../channels/p2p_channel.dart';
import '../models/post.dart';
import '../models/room.dart';
import '../models/shared_file.dart';
import '../providers/feed_provider.dart';
import '../providers/identity_provider.dart';
import '../providers/mesh_debug_provider.dart';
import '../providers/peer_provider.dart';
import '../providers/room_provider.dart';
import '../providers/shared_file_provider.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String? _loadedRoomId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRoomFeed();
  }

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomProvider>();
    final activeRoom = roomProvider.activeRoom;
    final posts = context.watch<FeedProvider>().posts;
    final files = context.watch<SharedFileProvider>().files;
    final p2pConnected = context.watch<PeerProvider>().p2pConnected;
    final debug = context.watch<MeshDebugProvider>();
    final roomIsEmpty = posts.isEmpty && files.isEmpty;

    if (activeRoom != null && _loadedRoomId != activeRoom.roomId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncRoomFeed());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('MeshSocial'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: activeRoom == null ? null : () => _pickAndSendFile(context, activeRoom),
            icon: const Icon(Icons.attach_file),
            tooltip: 'Share file',
          ),
          IconButton(
            onPressed: () => _showJoinRoomDialog(context),
            icon: const Icon(Icons.lock_open),
            tooltip: 'Join room',
          ),
          IconButton(
            onPressed: () => _showCreateRoomDialog(context),
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create room',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: activeRoom == null ? null : () => _showPostDialog(context, activeRoom),
        icon: const Icon(Icons.edit),
        label: const Text('Post'),
      ),
      body: Column(
        children: [
          _RoomHeader(
            activeRoom: activeRoom,
            rooms: roomProvider.rooms,
            onSelectRoom: (room) async {
              roomProvider.setActiveRoom(room);
              await context.read<FeedProvider>().loadPosts(roomId: room.roomId);
              if (!mounted) return;
              setState(() {
                _loadedRoomId = room.roomId;
              });
            },
          ),
          if (debug.lastError != null || debug.lastAppliedAt != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    p2pConnected ? Icons.hub : Icons.portable_wifi_off,
                    color: p2pConnected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p2pConnected ? 'Mesh link live' : 'Mesh link offline',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (debug.lastPushAt != null)
                          Text(
                            'Last push: ${debug.lastPushedPostCount} posts',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        if (debug.lastAppliedAt != null)
                          Text(
                            'Last receive: ${debug.lastAppliedCount} posts',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        if (debug.lastError != null)
                          Text(
                            debug.lastError!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: activeRoom == null
                ? const Center(child: CircularProgressIndicator())
                : roomIsEmpty
                    ? _EmptyFeedState(
                        activeRoom: activeRoom,
                        p2pConnected: p2pConnected,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                        children: [
                          _FileShelf(files: files),
                          const SizedBox(height: 14),
                          ...posts.map(
                            (post) => _PostCard(
                              post: post,
                              isLocalAuthor: post.authorId ==
                                  context.read<IdentityProvider>().identity?.peerId,
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  void _syncRoomFeed() {
    final room = context.read<RoomProvider>().activeRoom;
    if (room == null) return;
    context.read<FeedProvider>().loadPosts(roomId: room.roomId);
    context.read<SharedFileProvider>().loadFiles(roomId: room.roomId);
    _loadedRoomId = room.roomId;
  }

  Future<void> _pickAndSendFile(BuildContext context, Room room) async {
    final identity = context.read<IdentityProvider>().identity;
    if (identity == null) return;

    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    if (path == null || path.isEmpty) return;

    const maxBytes = 4 * 1024 * 1024;
    if (picked.size > maxBytes) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('First version supports files up to 4 MB.')),
      );
      return;
    }

    final file = await context.read<SharedFileProvider>().addOutgoingFile(
          roomId: room.roomId,
          roomName: room.name,
          senderId: identity.peerId,
          senderName: identity.displayName,
          sourcePath: path,
          fileName: picked.name,
          fileSize: picked.size,
          mimeType: _guessMimeType(picked.name),
        );

    try {
      await P2PChannel.sendFile(
        path: path,
        fileId: file.fileId,
        fileName: file.fileName,
        fileSize: file.fileSize,
        mimeType: file.mimeType,
        roomId: room.roomId,
        roomName: room.name,
        senderId: identity.peerId,
        senderName: identity.displayName,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shared ${file.fileName} in ${room.name}.')),
      );
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    }
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  void _showPostDialog(BuildContext context, Room room) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Post in ${room.name}'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: "What's happening in this room?",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final identity = context.read<IdentityProvider>().identity;
              final text = controller.text.trim();
              if (identity != null && text.isNotEmpty) {
                await context.read<FeedProvider>().createPost(
                      text,
                      identity.peerId,
                      identity.displayName,
                      roomId: room.roomId,
                      roomName: room.name,
                    );
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
                        ),
                      );
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

  void _showCreateRoomDialog(BuildContext context) {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    bool locked = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Create room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Room name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: locked,
                onChanged: (value) => setLocalState(() => locked = value),
                title: const Text('Lock with password'),
                contentPadding: EdgeInsets.zero,
              ),
              if (locked)
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final password = locked ? passwordController.text : '';
                if (name.isEmpty) return;
                final room = await context.read<RoomProvider>().createRoom(
                      name: name,
                      password: password,
                    );
                await context.read<FeedProvider>().loadPosts(roomId: room.roomId);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinRoomDialog(BuildContext context) {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Room name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password if locked',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final room = await context.read<RoomProvider>().joinRoom(
                    roomName: nameController.text,
                    password: passwordController.text,
                  );
              if (!ctx.mounted) return;
              if (room == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Room password did not match.')),
                );
                return;
              }
              await context.read<FeedProvider>().loadPosts(roomId: room.roomId);
              Navigator.pop(ctx);
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

class _FileShelf extends StatelessWidget {
  final List<SharedFile> files;

  const _FileShelf({required this.files});

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('No files shared in this room yet.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Shared files',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 126,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: files.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _FileCard(file: files[index]),
          ),
        ),
      ],
    );
  }
}

class _FileCard extends StatelessWidget {
  final SharedFile file;

  const _FileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${file.fileSize ~/ 1024} KB',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'By ${file.senderName}',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            DateFormat('MMM d, HH:mm').format(file.createdAt),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  final Room? activeRoom;
  final List<Room> rooms;
  final ValueChanged<Room> onSelectRoom;

  const _RoomHeader({
    required this.activeRoom,
    required this.rooms,
    required this.onSelectRoom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      activeRoom?.isLocked == true ? Icons.lock : Icons.forum,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      activeRoom?.name ?? 'Loading room...',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rooms.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final room = rooms[index];
                final selected = activeRoom?.roomId == room.roomId;
                return ChoiceChip(
                  selected: selected,
                  onSelected: (_) => onSelectRoom(room),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (room.isLocked) ...[
                        const Icon(Icons.lock, size: 14),
                        const SizedBox(width: 6),
                      ],
                      Text(room.name),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _EmptyFeedState extends StatelessWidget {
  final Room activeRoom;
  final bool p2pConnected;

  const _EmptyFeedState({
    required this.activeRoom,
    required this.p2pConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              activeRoom.isLocked ? Icons.lock_outline : Icons.chat_bubble_outline,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'No posts in ${activeRoom.name} yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              p2pConnected
                  ? 'Your mesh link is up. Start the conversation in this room.'
                  : 'Write the first post here, then connect on Nearby to sync with other phones.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Post post;
  final bool isLocalAuthor;

  const _PostCard({
    required this.post,
    required this.isLocalAuthor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLocalAuthor
            ? colorScheme.primaryContainer.withValues(alpha: 0.85)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                child: Text(
                  post.authorName.isNotEmpty ? post.authorName[0].toUpperCase() : '?',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _timeLabel(post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      post.synced ? Icons.cloud_done : Icons.schedule,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text('${post.hopCount} hops'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            post.content,
            style: const TextStyle(fontSize: 15, height: 1.45),
          ),
        ],
      ),
    );
  }

  String _timeLabel(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
