import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/identity_provider.dart';
import '../providers/mesh_debug_provider.dart';
import '../providers/peer_provider.dart';

class GossipController {
  final BuildContext context;
  
  GossipController(this.context);

  Future<dynamic> handleEvent(MethodCall call) async {
    switch (call.method) {
      case 'wifiP2PStateChanged':
        final bool enabled = call.arguments['enabled'];
        debugPrint('WiFi P2P enabled: $enabled');
        break;

      case 'discoveryStateChanged':
        final bool isDiscovering = call.arguments['isDiscovering'];
        context.read<PeerProvider>().setDiscoveryState(isDiscovering);
        break;

      case 'clearDiscoveredPeers':
        context.read<PeerProvider>().clearDiscoveredPeers();
        break;

      case 'peersDiscovered':
        final List<dynamic> peersData = call.arguments['peers'];
        context.read<PeerProvider>().handlePeersDiscovered(
              peersData.map((p) => Map<String, dynamic>.from(p)).toList(),
            );
        break;

      case 'connectionStateChanged':
        final bool isConnected = call.arguments['isConnected'] as bool? ?? false;
        final bool? isGroupOwner = call.arguments['isGroupOwner'] as bool?;
        final String groupOwnerAddress =
            call.arguments['groupOwnerAddress'] as String? ?? '';
        final int peerCount =
            (call.arguments['peerCount'] as num?)?.toInt() ?? 0;
        if (!context.mounted) break;
        context.read<PeerProvider>().setP2pConnection(
              connected: isConnected,
              isGroupOwner: isGroupOwner,
              groupOwnerHost: groupOwnerAddress,
              peerCount: peerCount,
            );
        break;

      case 'gossipTransportReady':
        if (context.mounted) {
          final int peerCount =
              (call.arguments['peerCount'] as num?)?.toInt() ?? 0;
          final peerProvider = context.read<PeerProvider>();
          context.read<PeerProvider>().setP2pConnection(
                connected: true,
                isGroupOwner: peerProvider.isGroupOwner,
                groupOwnerHost: peerProvider.groupOwnerHost,
                peerCount: peerCount,
              );
        }
        break;

      // Delta Sync Flow
      case 'getGossipHelloExport':
        if (!context.mounted) return null;
        final identity = context.read<IdentityProvider>().identity;
        final feed = context.read<FeedProvider>();
        if (identity == null) return {'peerId': '', 'postIds': <String>[]};
        return {
          'peerId': identity.peerId,
          'postIds': await feed.exportPostIdsForSync(),
        };

      case 'gossipProcessHello':
        if (!context.mounted) return null;
        final identity = context.read<IdentityProvider>().identity;
        if (identity == null) return null;
        
        final list = call.arguments['theirIds'] as List<dynamic>? ?? [];
        final theirIds = list.map((e) => e.toString()).toSet();
        
        final feed = context.read<FeedProvider>();
        final myPostIdsList = await feed.exportPostIdsForSync();
        final myPostIds = myPostIdsList.toSet();
        
        // 1. What DO WE HAVE that THEY DO NOT? (Posts we will give them)
        final missingIds = myPostIds.where((id) => !theirIds.contains(id)).toList();
        
        // 2. What do THEY HAVE that WE DO NOT? (Posts we will ask them for)
        final requestedIds = theirIds.where((id) => !myPostIds.contains(id)).toList();
        
        return {
            'peerId': identity.peerId,
            'missingPosts': await feed.exportSpecificPosts(missingIds),
            'requestIds': requestedIds
        };

      case 'gossipProcessSyncRequests':
        if (!context.mounted) return null;
        final identity = context.read<IdentityProvider>().identity;
        if (identity == null) return null;

        final list = call.arguments['requestIds'] as List<dynamic>? ?? [];
        final requestIdsList = list.map((e) => e.toString()).toList();

        final feed = context.read<FeedProvider>();
        return {
            'peerId': identity.peerId,
            'missingPosts': await feed.exportSpecificPosts(requestIdsList)
        };

      case 'gossipApplyPosts':
        if (!context.mounted) return null;
        final list = call.arguments['posts'] as List<dynamic>? ?? [];
        final feed = context.read<FeedProvider>();
        await feed.applyPostsFromGossip(list);
        return null;

      case 'getPeerId':
        if (!context.mounted) return null;
        return context.read<IdentityProvider>().identity?.peerId;

      case 'meshDebugPushSent':
      case 'meshDebugApplied':
      case 'meshDebugError':
      case 'meshDebugPingReceived':
        _handleDebugEvents(call);
        break;

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

  void _handleDebugEvents(MethodCall call) {
    if (!context.mounted) return;
    switch (call.method) {
      case 'meshDebugPushSent':
        final postCount = call.arguments['postCount'] as int? ?? 0;
        context.read<MeshDebugProvider>().setPush(postCount: postCount);
        break;
      case 'meshDebugApplied':
        final mergedCount = call.arguments['mergedCount'] as int? ?? 0;
        final needsAck = call.arguments['needsAck'] as bool? ?? false;
        context.read<MeshDebugProvider>().setReceived(
              mergedCount: mergedCount,
              needsAck: needsAck,
            );
        context.read<MeshDebugProvider>().setApplied(count: mergedCount);
        break;
      case 'meshDebugError':
        final msg = call.arguments['message'] as String? ?? 'Unknown error';
        context.read<MeshDebugProvider>().setError(msg);
        break;
      case 'meshDebugPingReceived':
        final payload = call.arguments['payload'] as String? ?? '';
        context.read<MeshDebugProvider>().setDebugPingReceived(payload: payload);
        break;
    }
  }
}
