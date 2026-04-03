import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'channels/p2p_channel.dart';
import 'providers/feed_provider.dart';
import 'providers/identity_provider.dart';
import 'providers/mesh_debug_provider.dart';
import 'providers/peer_provider.dart';
import 'controllers/gossip_controller.dart';

/// MeshSocial: **Flutter = UI + local persistence**. **Kotlin = Wi‑Fi Direct, TCP gossip, protocol.**
/// Target: **Android only** (iOS not used for this build).
class MeshSocialApp extends StatefulWidget {
  const MeshSocialApp({super.key});

  @override
  State<MeshSocialApp> createState() => _MeshSocialAppState();
}

class _MeshSocialAppState extends State<MeshSocialApp> {
  late final GossipController _gossipController;

  @override
  void initState() {
    super.initState();
    _gossipController = GossipController(context);
    P2PChannel.setEventHandler(_gossipController.handleEvent);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshSocial',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
