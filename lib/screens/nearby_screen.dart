import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../channels/p2p_channel.dart';
import '../models/peer.dart';
import '../p2p_permissions.dart';
import '../providers/mesh_debug_provider.dart';
import '../providers/peer_provider.dart';

Future<void> _toggleWifiScan(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final peerProvider = context.read<PeerProvider>();
  final isDiscovering = peerProvider.wifiDiscovering;

  void showErr(String msg) {
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    showErr('Wi-Fi Direct scanning only works on a physical Android device.');
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
          'Allow Location or Nearby Wi-Fi devices to scan over Wi-Fi Direct.',
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
    showErr('Native Wi-Fi Direct is not available on this platform build.');
  }
}

Future<void> _connectToPeer(BuildContext context, Peer peer) async {
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
        content: const Text('Grant Wi-Fi Direct permissions first.'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () => openAppSettings(),
        ),
      ),
    );
    return;
  }

  try {
    await P2PChannel.connectToPeer(peer.deviceAddress);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Wi-Fi Direct invite sent. Keep both phones nearby until connected.',
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Open Wi-Fi',
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

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _statusColor(PeerStatus s) => switch (s) {
        PeerStatus.connected => Colors.green,
        PeerStatus.discovered => Colors.orange,
        PeerStatus.disconnected => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final peerProvider = context.watch<PeerProvider>();
    final peers = peerProvider.peers;
    final query = _searchQuery.trim().toLowerCase();
    final filteredPeers = query.isEmpty
        ? peers
        : peers.where((peer) {
            final name = peer.displayName.toLowerCase();
            final address = peer.deviceAddress.toLowerCase();
            return name.contains(query) || address.contains(query);
          }).toList();
    final wifiDiscovering = peerProvider.wifiDiscovering;
    final wifiConnected = peerProvider.wifiConnected;
    final isGo = peerProvider.isGroupOwner;
    final debug = context.watch<MeshDebugProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Peers'),
        actions: [
          if (wifiDiscovering)
            const Padding(
              padding: EdgeInsets.all(16.0),
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
      body: Column(
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _toggleWifiScan(context),
                    icon: Icon(wifiDiscovering ? Icons.stop : Icons.wifi),
                    label: Text(wifiDiscovering ? 'Stop Wi-Fi' : 'Scan Wi-Fi'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search devices by name or address',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Mesh raw debug',
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
                          context.read<MeshDebugProvider>().setError(e.toString());
                        }
                      },
                      child: const Text('Send debug ping'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!wifiConnected)
            Material(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 22,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Scan over Wi-Fi Direct, then tap Connect on a discovered peer.',
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
          if (wifiConnected)
            Material(
              color: Colors.green.shade100,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.wifi, color: Colors.green),
                title: Text(
                  isGo == true
                      ? 'Wi-Fi Direct link up - you are group owner'
                      : 'Wi-Fi Direct link up',
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
                          'No peers found yet.\nScan Wi-Fi Direct to start.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _toggleWifiScan(context),
                          child: const Text('Scan Wi-Fi'),
                        ),
                      ],
                    ),
                  )
                : filteredPeers.isEmpty
                    ? Center(
                        child: Text(
                          'No devices match "${_searchQuery.trim()}".',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredPeers.length,
                        itemBuilder: (ctx, i) {
                          final peer = filteredPeers[i];
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
                            title: Text(
                              peer.displayName.isNotEmpty
                                  ? peer.displayName
                                  : 'Unknown Device',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  peer.deviceAddress,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                Text(
                                  'Last seen: ${_formatTime(peer.lastSeen)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            trailing: wifiConnected
                                ? ElevatedButton(
                                    onPressed: P2PChannel.disconnect,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Disconnect'),
                                  )
                                : peer.status == PeerStatus.discovered
                                    ? ElevatedButton(
                                        onPressed: () => _connectToPeer(context, peer),
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
