import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wi‑Fi Direct peer discovery on Android requires runtime permission:
/// - **Android 12 and below:** approximate/fine location (system maps this for scanning).
/// - **Android 13+:** [Permission.nearbyWifiDevices] (see manifest `neverForLocation`).
bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Requests permissions and returns whether discovery is allowed to proceed.
Future<bool> ensureWifiDirectDiscoveryPermission() async {
  if (!_isAndroid) return false;

  final nearby = await Permission.nearbyWifiDevices.request();
  final location = await Permission.locationWhenInUse.request();

  if (nearby.isGranted) return true;
  if (location.isGranted) return true;
  return false;
}
