import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'channels/p2p_channel.dart';
import 'providers/feed_provider.dart';
import 'providers/identity_provider.dart';
import 'providers/mesh_debug_provider.dart';
import 'providers/peer_provider.dart';

/// MeshSocial: **Flutter = UI + local persistence**. **Kotlin = Wi‑Fi Direct, TCP gossip, protocol.**
/// Target: **Android only** (iOS not used for this build).
class MeshSocialApp extends StatefulWidget {
  const MeshSocialApp({super.key});

  @override
  State<MeshSocialApp> createState() => _MeshSocialAppState();
}

class _MeshSocialAppState extends State<MeshSocialApp> {
  @override
  void initState() {
    super.initState();
    P2PChannel.setEventHandler(_handleP2PEvent);
  }

  Future<dynamic> _handleP2PEvent(MethodCall call) async {
    switch (call.method) {
      case 'wifiP2PStateChanged':
        final bool enabled = call.arguments['enabled'];
        debugPrint('WiFi P2P enabled: $enabled');
        break;

      case 'discoveryStateChanged':
        final bool isDiscovering = call.arguments['isDiscovering'];
        context.read<PeerProvider>().setDiscoveryState(isDiscovering);
        break;

      case 'peersDiscovered':
        final List<dynamic> peersData = call.arguments['peers'];
        context.read<PeerProvider>().handlePeersDiscovered(
              peersData.map((p) => Map<String, dynamic>.from(p)).toList(),
            );
        break;

      case 'connectionStateChanged':
        final bool isConnected = call.arguments['isConnected'];
        if (!context.mounted) break;
        if (isConnected) {
          final bool isGroupOwner = call.arguments['isGroupOwner'] as bool;
          final String groupOwnerAddress =
              call.arguments['groupOwnerAddress'] as String? ?? '';
          context.read<PeerProvider>().setP2pConnection(
                connected: true,
                isGroupOwner: isGroupOwner,
                groupOwnerHost: groupOwnerAddress,
              );
        } else {
          context.read<PeerProvider>().setP2pConnection(connected: false);
        }
        break;

      case 'gossipTransportReady':
        // Native opened the TCP gossip socket; treat mesh link as up for UI.
        if (context.mounted) {
          context.read<PeerProvider>().setP2pConnection(connected: true);
        }
        break;

      case 'meshDebugPushSent':
        if (context.mounted) {
          final postCount = call.arguments['postCount'] as int? ?? 0;
          context.read<MeshDebugProvider>().setPush(postCount: postCount);
        }
        break;

      case 'meshDebugApplied':
        if (context.mounted) {
          final mergedCount = call.arguments['mergedCount'] as int? ?? 0;
          final needsAck = call.arguments['needsAck'] as bool? ?? false;
          context.read<MeshDebugProvider>().setReceived(
                mergedCount: mergedCount,
                needsAck: needsAck,
              );
          context.read<MeshDebugProvider>().setApplied(count: mergedCount);
        }
        break;

      case 'meshDebugError':
        if (context.mounted) {
          final msg = call.arguments['message'] as String? ?? 'Unknown error';
          context.read<MeshDebugProvider>().setError(msg);
        }
        break;

      case 'meshDebugPingReceived':
        if (context.mounted) {
          final payload = call.arguments['payload'] as String? ?? '';
          context.read<MeshDebugProvider>().setDebugPingReceived(payload: payload);
        }
        break;

      /// Kotlin [GossipEngine] requests current posts + peer id for sync frames.
      case 'getGossipExport':
        if (!context.mounted) return null;
        final identity = context.read<IdentityProvider>().identity;
        final feed = context.read<FeedProvider>();
        if (identity == null) {
          return {'peerId': '', 'posts': <dynamic>[]};
        }
        return {
          'peerId': identity.peerId,
          'posts': await feed.exportPostsForSync(),
        };

      /// Apply merged posts from peer, return fresh export for native [buildAckEnvelope].
      case 'gossipApplyPosts':
        if (!context.mounted) return null;
        final list = call.arguments['posts'] as List<dynamic>? ?? [];
        final feed = context.read<FeedProvider>();
        final identityProv = context.read<IdentityProvider>();
        await feed.applyPostsFromGossip(list);
        final id = identityProv.identity;
        if (id == null) {
          return {'peerId': '', 'posts': <dynamic>[]};
        }
        return {
          'peerId': id.peerId,
          'posts': await feed.exportPostsForSync(),
        };

      case 'gossipMarkOwnSynced':
        if (!context.mounted) return null;
        final peerId = call.arguments['peerId'] as String?;
        if (peerId != null && peerId.isNotEmpty) {
          await context.read<FeedProvider>().markOwnPostsSynced(peerId);
        }
        return null;

      case 'thisDeviceChanged':
        final String deviceName = call.arguments['deviceName'];
        final String deviceAddress = call.arguments['deviceAddress'];
        debugPrint('This device: $deviceName ($deviceAddress)');
        break;

      default:
        debugPrint('Unknown P2P event: ${call.method}');
    }
    return null;
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
