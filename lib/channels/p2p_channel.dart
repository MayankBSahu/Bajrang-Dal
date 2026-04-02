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

  static Future<void> sendGossipPayload(
      String deviceAddress, String jsonPayload) async {
    await _channel.invokeMethod('sendGossipPayload', {
      'address': deviceAddress,
      'payload': jsonPayload,
    });
  }

  static Future<String?> getDeviceAddress() async {
    return await _channel.invokeMethod<String>('getDeviceAddress');
  }
}