import 'package:flutter/services.dart';

class P2PChannel {
  static const MethodChannel _channel = MethodChannel('meshsocial/p2p');

  // Called from Kotlin → Flutter (events coming up)
  static void setEventHandler(Future<dynamic> Function(MethodCall) handler) {
    _channel.setMethodCallHandler(handler);
  }

  // Flutter → Kotlin calls
  static Future<void> startDiscovery() async {
    await _channel.invokeMethod('startDiscovery');
  }

  static Future<void> stopDiscovery() async {
    await _channel.invokeMethod('stopDiscovery');
  }

  static Future<void> connectToPeer(String deviceAddress) async {
    await _channel.invokeMethod('connectToPeer', {'address': deviceAddress});
  }

  static Future<void> disconnect() async {
    await _channel.invokeMethod('disconnect');
  }

  /// Sends a UTF-8 JSON payload over the active Wi‑Fi Direct gossip socket.
  /// [deviceAddress] is reserved for future multi-peer routing; native may ignore it.
  static Future<void> sendGossipPayload(String jsonPayload,
      {String deviceAddress = ''}) async {
    await _channel.invokeMethod('sendGossipPayload', {
      'address': deviceAddress,
      'payload': jsonPayload,
    });
  }

  static Future<String?> getDeviceAddress() async {
    return await _channel.invokeMethod<String>('getDeviceAddress');
  }

  /// System Wi‑Fi screen (user may find Wi‑Fi Direct / invites there on some phones).
  static Future<void> openWifiSettings() async {
    await _channel.invokeMethod('openWifiSettings');
  }

  /// Push current posts to the peer over the open gossip socket (call after creating a post).
  static Future<void> pushGossipSync() async {
    await _channel.invokeMethod('pushGossipSync');
  }

  /// Ground test: send a raw debug marker over the gossip TCP socket.
  /// The other side will report receipt without applying to the feed/DB.
  static Future<void> sendDebugPing(String payload) async {
    await _channel.invokeMethod('sendDebugPing', {'payload': payload});
  }

  static Future<void> sendFile({
    required String path,
    required String fileId,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String roomId,
    required String roomName,
    required String senderId,
    required String senderName,
    String deviceAddress = '',
  }) async {
    await _channel.invokeMethod('sendFile', {
      'path': path,
      'fileId': fileId,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'roomId': roomId,
      'roomName': roomName,
      'senderId': senderId,
      'senderName': senderName,
      'address': deviceAddress,
    });
  }
}
