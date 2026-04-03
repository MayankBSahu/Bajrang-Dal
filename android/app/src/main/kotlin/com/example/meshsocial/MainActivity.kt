package com.example.meshsocial

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Flutter UI + Dart DB; [P2PManager] + [GossipEngine] implement mesh. Android-only target. */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "meshsocial/p2p"
    private lateinit var p2pManager: P2PManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        p2pManager = P2PManager(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startDiscovery"     -> p2pManager.startDiscovery(result)
                    "stopDiscovery"      -> p2pManager.stopDiscovery(result)
                    "connectToPeer"      -> {
                        val address = call.argument<String>("address") ?: ""
                        p2pManager.connectToPeer(address, result)
                    }
                    "disconnect"         -> p2pManager.disconnect(result)
                    "sendGossipPayload"  -> {
                        val address = call.argument<String>("address") ?: ""
                        val payload = call.argument<String>("payload") ?: ""
                        p2pManager.sendGossipPayload(address, payload, result)
                    }
                    "getDeviceAddress"   -> p2pManager.getDeviceAddress(result)
                    "openWifiSettings"   -> p2pManager.openWifiSettings(result)
                    "pushGossipSync"    -> p2pManager.pushGossipSync(result)
                    "sendDebugPing"     -> {
                        val payload = call.argument<String>("payload") ?: "DEBUG_PING|unknown"
                        p2pManager.sendDebugPing(payload, result)
                    }
                    else                 -> result.notImplemented()
                }
            }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        p2pManager.cleanup()
    }
}