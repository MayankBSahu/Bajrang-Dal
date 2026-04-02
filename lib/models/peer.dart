enum PeerStatus { discovered, connected, disconnected }

class Peer {
  final String peerId;
  final String displayName;
  final String deviceAddress;   // WiFi Direct MAC / BLE address
  PeerStatus status;
  DateTime lastSeen;

  Peer({
    required this.peerId,
    required this.displayName,
    required this.deviceAddress,
    this.status = PeerStatus.discovered,
    required this.lastSeen,
  });

  Map<String, dynamic> toMap() => {
    'peer_id': peerId,
    'display_name': displayName,
    'device_address': deviceAddress,
    'status': status.name,
    'last_seen': lastSeen.toIso8601String(),
  };

  factory Peer.fromMap(Map<String, dynamic> m) => Peer(
    peerId: m['peer_id'],
    displayName: m['display_name'],
    deviceAddress: m['device_address'],
    status: PeerStatus.values.byName(m['status'] ?? 'discovered'),
    lastSeen: DateTime.parse(m['last_seen']),
  );
}