class Identity {
  final String peerId;      // UUID, generated once
  final String displayName;
  final String publicKey;   // placeholder for Phase 3 signing
  final DateTime createdAt;

  Identity({
    required this.peerId,
    required this.displayName,
    required this.publicKey,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'peer_id': peerId,
    'display_name': displayName,
    'public_key': publicKey,
    'created_at': createdAt.toIso8601String(),
  };

  factory Identity.fromMap(Map<String, dynamic> m) => Identity(
    peerId: m['peer_id'],
    displayName: m['display_name'],
    publicKey: m['public_key'],
    createdAt: DateTime.parse(m['created_at']),
  );
}