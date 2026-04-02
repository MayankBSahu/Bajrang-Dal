package com.example.meshsocial

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle

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
                    else                 -> result.notImplemented()
                }
            }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        p2pManager.cleanup()
    }
}