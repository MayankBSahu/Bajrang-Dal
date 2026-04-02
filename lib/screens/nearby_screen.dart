import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/peer_provider.dart';
import '../models/peer.dart';
import '../channels/p2p_channel.dart';

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
        onPressed: isDiscovering ? P2PChannel.stopDiscovery : P2PChannel.startDiscovery,
        icon: Icon(isDiscovering ? Icons.stop : Icons.search),
        label: Text(isDiscovering ? 'Stop' : 'Scan'),
      ),
      body: peers.isEmpty
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
                      onPressed: P2PChannel.startDiscovery,
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
                  title: Text(peer.displayName.isNotEmpty ? peer.displayName : 'Unknown Device'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(peer.deviceAddress,
                          style: const TextStyle(fontSize: 11)),
                      Text('Last seen: ${_formatTime(peer.lastSeen)}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  trailing: peer.status == PeerStatus.discovered
                      ? ElevatedButton(
                          onPressed: () => P2PChannel.connectToPeer(peer.deviceAddress),
                          child: const Text('Connect'),
                        )
                      : peer.status == PeerStatus.connected
                          ? ElevatedButton(
                              onPressed: P2PChannel.disconnect,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              child: const Text('Disconnect'),
                            )
                          : Chip(
                              label: Text(peer.status.name),
                              backgroundColor: _statusColor(peer.status).withOpacity(0.15),
                            ),
                );
              },
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