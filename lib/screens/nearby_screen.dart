import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../channels/p2p_channel.dart';
import '../models/peer.dart';
import '../p2p_permissions.dart';
import '../providers/peer_provider.dart';
import '../providers/mesh_debug_provider.dart';

Future<void> _toggleNearbyScan(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final peerProvider = context.read<PeerProvider>();
  final isDiscovering = peerProvider.isDiscovering;

  void showErr(String msg) {
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    showErr('Wi‑Fi Direct scanning only works on a physical Android device.');
    return;
  }

  if (isDiscovering) {
    try {
      await P2PChannel.stopDiscovery();
    } on PlatformException catch (e) {
      showErr(e.message ?? e.code);
    }
    return;
  }

  final allowed = await ensureWifiDirectDiscoveryPermission();
  if (!context.mounted) return;
  if (!allowed) {
    messenger?.showSnackBar(
      SnackBar(
        content: const Text(
          'Allow Location (Android 12 and below) or Nearby Wi‑Fi devices (Android 13+) to scan.',
        ),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () => openAppSettings(),
        ),
      ),
    );
    return;
  }

  try {
    await P2PChannel.startDiscovery();
  } on PlatformException catch (e) {
    showErr(e.message ?? e.code);
  } on MissingPluginException {
    showErr('Native Wi‑Fi Direct is not available on this platform build.');
  }
}


Future<void> _connectToPeer(BuildContext context, String deviceAddress) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Connect requires an Android device.')),
    );
    return;
  }

  final messenger = ScaffoldMessenger.maybeOf(context);
  final allowed = await ensureWifiDirectDiscoveryPermission();
  if (!context.mounted) return;
  if (!allowed) {
    messenger?.showSnackBar(
      SnackBar(
        content: const Text('Grant Location or Nearby Wi‑Fi permission first.'),
        action: SnackBarAction(label: 'Settings', onPressed: () => openAppSettings()),
      ),
    );
    return;
  }
  try {
    await P2PChannel.connectToPeer(deviceAddress);
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Invite sent! The other phone must accept the prompt (check notifications or Wi‑Fi settings).'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Open Wi‑Fi',
          onPressed: () => P2PChannel.openWifiSettings(),
        ),
      ),
    );

  } on PlatformException catch (e) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(e.message ?? e.code),
        duration: const Duration(seconds: 10),
      ),
    );
  } on MissingPluginException {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Connect requires the Android app.')),
    );
  }
}

class NearbyScreen extends StatelessWidget {
  const NearbyScreen({super.key});

  Color _statusColor(PeerStatus s) => switch (s) {
    PeerStatus.connected => Colors.green,
    PeerStatus.discovered => Colors.orange,
    PeerStatus.disconnected => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final peers = context.watch<PeerProvider>().peers;
    final isDiscovering = context.watch<PeerProvider>().isDiscovering;
    
    final p2pConnected = context.watch<PeerProvider>().p2pConnected;
    final isGo = context.watch<PeerProvider>().isGroupOwner;
    final debug = context.watch<MeshDebugProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Peers'),
        actions: [
          if (isDiscovering)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _toggleNearbyScan(context),
        icon: Icon(isDiscovering ? Icons.stop : Icons.search),
        label: Text(isDiscovering ? 'Stop' : 'Scan'),
      ),
      body: Column(
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mesh raw debug (TCP delivery)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (debug.lastDebugPingSentAt != null)
                    Text(
                      'Sent: ${debug.lastDebugPingSentPayload ?? ''}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  if (debug.lastDebugPingReceivedAt != null)
                    Text(
                      'Received: ${debug.lastDebugPingReceivedPayload ?? ''}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  if (debug.lastError != null)
                    Text(
                      'Error: ${debug.lastError}',
                      style: const TextStyle(fontSize: 12.5, color: Colors.red),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final payload =
                            'DEBUG_PING|${DateTime.now().millisecondsSinceEpoch}';
                        try {
                          await P2PChannel.sendDebugPing(payload);
                          if (!context.mounted) return;
                          context
                              .read<MeshDebugProvider>()
                              .setDebugPingSent(payload: payload);
                        } catch (e) {
                          if (!context.mounted) return;
                          context
                              .read<MeshDebugProvider>()
                              .setError(e.toString());
                        }
                      },
                      child: const Text('Send debug ping'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!p2pConnected)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 22,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'After you tap Connect, an invite will be sent. The other phone '
                        'must Accept it from their notifications or Wi‑Fi settings. '
                        'Keep Scan ON on both phones until connected.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (p2pConnected)
            Material(
              color: Colors.green.shade100,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.link, color: Colors.green),
                title: Text(
                  isGo == true
                      ? 'P2P link up — you are group owner (gossip relay)'
                      : 'P2P link up — connected to group owner',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          Expanded(
            child: peers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'No peers found yet.\nTap Scan to start.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (!isDiscovering)
                          ElevatedButton(
                            onPressed: () => _toggleNearbyScan(context),
                            child: const Text('Start Scanning'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (ctx, i) {
                      final peer = peers[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(peer.status),
                          child: Text(
                            peer.displayName.isNotEmpty
                                ? peer.displayName[0].toUpperCase()
                                : 'P',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(peer.displayName.isNotEmpty
                            ? peer.displayName
                            : 'Unknown Device'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(peer.deviceAddress,
                                style: const TextStyle(fontSize: 11)),
                            Text('Last seen: ${_formatTime(peer.lastSeen)}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        trailing: p2pConnected
                            ? ElevatedButton(
                                onPressed: P2PChannel.disconnect,
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                child: const Text('Disconnect'),
                              )
                            : peer.status == PeerStatus.discovered
                                ? ElevatedButton(
                                    onPressed: () => _connectToPeer(
                                        context, peer.deviceAddress),
                                    child: const Text('Connect'),
                                  )
                                : Chip(
                                    label: Text(peer.status.name),
                                    backgroundColor: _statusColor(peer.status)
                                        .withValues(alpha: 0.15),
                                  ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }
}
