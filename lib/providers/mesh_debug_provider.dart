import 'package:flutter/foundation.dart';

/// Simple, visible debug state for Phase "ground working".
/// Helps confirm whether native actually sent and whether the peer applied posts.
class MeshDebugProvider extends ChangeNotifier {
  DateTime? lastPushAt;
  int lastPushedPostCount = 0;

  DateTime? lastReceivedAt;
  int lastReceivedMergedCount = 0;
  bool? lastReceivedNeedsAck;

  DateTime? lastAppliedAt;
  int lastAppliedCount = 0;

  // Raw debug ping (ground working confirmation).
  // This is independent from CRDT/DB merge, so you can verify TCP delivery.
  DateTime? lastDebugPingSentAt;
  String? lastDebugPingSentPayload;

  DateTime? lastDebugPingReceivedAt;
  String? lastDebugPingReceivedPayload;

  String? lastError;

  void setPush({required int postCount}) {
    lastPushAt = DateTime.now();
    lastPushedPostCount = postCount;
    lastError = null;
    notifyListeners();
  }

  void setReceived({
    required int mergedCount,
    required bool needsAck,
  }) {
    lastReceivedAt = DateTime.now();
    lastReceivedMergedCount = mergedCount;
    lastReceivedNeedsAck = needsAck;
    notifyListeners();
  }

  void setApplied({required int count}) {
    lastAppliedAt = DateTime.now();
    lastAppliedCount = count;
    notifyListeners();
  }

  void setError(String message) {
    lastError = message;
    notifyListeners();
  }

  void setDebugPingSent({required String payload}) {
    lastDebugPingSentAt = DateTime.now();
    lastDebugPingSentPayload = payload;
    notifyListeners();
  }

  void setDebugPingReceived({required String payload}) {
    lastDebugPingReceivedAt = DateTime.now();
    lastDebugPingReceivedPayload = payload;
    notifyListeners();
  }
}

