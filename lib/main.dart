import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/identity_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/peer_provider.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => IdentityProvider()..load()),
        ChangeNotifierProvider(create: (_) => FeedProvider()..loadPosts()),
        ChangeNotifierProvider(create: (_) => PeerProvider()..loadPeers()),
      ],
      child: const MeshSocialApp(),
    ),
  );
}