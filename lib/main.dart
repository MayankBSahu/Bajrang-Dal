import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/feed_provider.dart';
import 'providers/identity_provider.dart';
import 'providers/mesh_debug_provider.dart';
import 'providers/peer_provider.dart';
import 'providers/room_provider.dart';

/// Entry: Flutter UI. Wi‑Fi Direct, TCP, and gossip protocol live in Android Kotlin (see `P2PManager` / `GossipEngine`).
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => IdentityProvider()..load()),
        ChangeNotifierProvider(create: (_) => FeedProvider()..loadPosts()),
        ChangeNotifierProvider(create: (_) => MeshDebugProvider()),
        ChangeNotifierProvider(create: (_) => PeerProvider()..loadPeers()),
        ChangeNotifierProvider(create: (_) => RoomProvider()..loadRooms()),
      ],
      child: const MeshSocialApp(),
    ),
  );
}
