import 'package:flutter/foundation.dart';
import '../models/peer.dart';
import '../db/database_helper.dart';

class PeerProvider extends ChangeNotifier {
  List<Peer> _peers = [];
  List<Peer> get peers => _peers;
  bool _wifiDiscovering = false;
  bool get wifiDiscovering => _wifiDiscovering;
  bool get isDiscovering => _wifiDiscovering;

  bool _wifiConnected = false;
  bool get wifiConnected => _wifiConnected;
  bool get p2pConnected => _wifiConnected;
  bool? _isGroupOwner;
  bool? get isGroupOwner => _isGroupOwner;
  String? _groupOwnerHost;
  String? get groupOwnerHost => _groupOwnerHost;
  int _peerCount = 0;
  int get peerCount => _peerCount;

  void setP2pConnection({
    required bool connected,
    bool? isGroupOwner,
    String? groupOwnerHost,
    int? peerCount,
  }) {
    _wifiConnected = connected;
    _isGroupOwner = isGroupOwner;
    _groupOwnerHost = groupOwnerHost;
    _peerCount = connected ? (peerCount ?? _peerCount) : 0;
    notifyListeners();
  }

  Future<void> loadPeers() async {
    _peers = await DatabaseHelper.instance.getKnownPeers();
    notifyListeners();
  }

  Future<void> upsertPeer(Peer peer) async {
    await DatabaseHelper.instance.upsertPeer(peer);
    final idx = _peers.indexWhere((p) => p.peerId == peer.peerId);
    if (idx >= 0) {
      _peers[idx] = peer;
    } else {
      _peers.add(peer);
    }
    notifyListeners();
  }

  void updateStatus(String deviceAddress, PeerStatus status) {
    final idx = _peers.indexWhere((p) => p.deviceAddress == deviceAddress);
    if (idx >= 0) {
      _peers[idx].status = status;
      notifyListeners();
    }
  }

  void setDiscoveryState(bool isDiscovering) {
    _wifiDiscovering = isDiscovering;
    notifyListeners();
  }

  void clearDiscoveredPeers() {
    _peers = [];
    notifyListeners();
  }

  void handlePeersDiscovered(List<Map<String, dynamic>> peersData) {
    for (final peerData in peersData) {
      final peer = Peer(
        peerId: peerData['deviceAddress'],
        displayName: peerData['deviceName'],
        deviceAddress: peerData['deviceAddress'],
        status: PeerStatus.discovered,
        lastSeen: DateTime.now(),
      );
      upsertPeer(peer);
    }
  }
}
