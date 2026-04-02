package com.example.meshsocial

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import java.net.InetAddress

class P2PManager(
    private val context: Context,
    messenger: BinaryMessenger
) {
    private val TAG = "MeshSocial-P2PManager"
    
    // This channel is used to PUSH events up to Flutter
    private val eventChannel = MethodChannel(messenger, "meshsocial/p2p")
    
    // WiFi Direct components
    private val wifiP2pManager: WifiP2pManager? by lazy(LazyThreadSafetyMode.NONE) {
        context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
    }
    private val channel: WifiP2pManager.Channel? by lazy(LazyThreadSafetyMode.NONE) {
        wifiP2pManager?.initialize(context, Looper.getMainLooper(), null)
    }
    
    // State tracking
    private var isDiscovering = false
    private var discoveredPeers = mutableListOf<WifiP2pDevice>()
    private var connectionInfo: WifiP2pInfo? = null
    private var thisDevice: WifiP2pDevice? = null
    
    // Broadcast receiver for WiFi Direct events
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    val isEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    notifyFlutter("wifiP2PStateChanged", mapOf("enabled" to isEnabled))
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    wifiP2pManager?.requestPeers(channel) { peers: WifiP2pDeviceList? ->
                        handleDiscoveredPeers(peers?.deviceList ?: emptyList())
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    handleConnectionChanged(intent)
                }
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    thisDevice = intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                    notifyFlutter("thisDeviceChanged", mapOf(
                        "deviceName" to (thisDevice?.deviceName ?: ""),
                        "deviceAddress" to (thisDevice?.deviceAddress ?: "")
                    ))
                }
            }
        }
    }
    
    // Intent filter for the broadcast receiver
    private val intentFilter = IntentFilter().apply {
        addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
        addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
        addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
    }
    
    init {
        // Register the broadcast receiver
        context.registerReceiver(receiver, intentFilter)
    }
    
    fun startDiscovery(result: MethodChannel.Result) {
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) 
            != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Location permission is required for WiFi Direct discovery", null)
            return
        }
        
        if (isDiscovering) {
            result.success(null)
            return
        }
        
        wifiP2pManager?.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Peer discovery started successfully")
                isDiscovering = true
                notifyFlutter("discoveryStateChanged", mapOf("isDiscovering" to true))
                result.success(null)
            }
            
            override fun onFailure(reason: Int) {
                Log.e(TAG, "Failed to start peer discovery: $reason")
                result.error("DISCOVERY_FAILED", "Failed to start peer discovery: $reason", null)
            }
        })
    }
    
    fun stopDiscovery(result: MethodChannel.Result) {
        if (!isDiscovering) {
            result.success(null)
            return
        }
        
        wifiP2pManager?.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Peer discovery stopped successfully")
                isDiscovering = false
                notifyFlutter("discoveryStateChanged", mapOf("isDiscovering" to false))
                result.success(null)
            }
            
            override fun onFailure(reason: Int) {
                Log.e(TAG, "Failed to stop peer discovery: $reason")
                result.error("STOP_DISCOVERY_FAILED", "Failed to stop peer discovery: $reason", null)
            }
        })
    }
    
    fun connectToPeer(address: String, result: MethodChannel.Result) {
        val device = discoveredPeers.find { it.deviceAddress == address }
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device with address $address not found", null)
            return
        }
        
        val config = WifiP2pConfig().apply {
            deviceAddress = address
            wps.setup = WpsInfo.PBC
        }
        
        wifiP2pManager?.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Connection to $address initiated successfully")
                result.success(null)
            }
            
            override fun onFailure(reason: Int) {
                Log.e(TAG, "Failed to connect to $address: $reason")
                result.error("CONNECTION_FAILED", "Failed to connect to peer: $reason", null)
            }
        })
    }
    
    fun disconnect(result: MethodChannel.Result) {
        wifiP2pManager?.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Disconnected successfully")
                connectionInfo = null
                notifyFlutter("connectionStateChanged", mapOf("isConnected" to false))
                result.success(null)
            }
            
            override fun onFailure(reason: Int) {
                Log.e(TAG, "Failed to disconnect: $reason")
                result.error("DISCONNECT_FAILED", "Failed to disconnect: $reason", null)
            }
        })
    }
    
    fun sendGossipPayload(address: String, payload: String, result: MethodChannel.Result) {
        // This will be implemented in Phase 2 with socket communication
        result.notImplemented()
    }
    
    fun getDeviceAddress(result: MethodChannel.Result) {
        result.success(thisDevice?.deviceAddress)
    }
    
    private fun handleDiscoveredPeers(devices: Collection<WifiP2pDevice>) {
        discoveredPeers.clear()
        discoveredPeers.addAll(devices)
        
        val peersList = devices.map { device ->
            mapOf(
                "deviceName" to device.deviceName,
                "deviceAddress" to device.deviceAddress,
                "status" to device.status.toString(),
                "isGroupOwner" to device.isGroupOwner
            )
        }
        
        notifyFlutter("peersDiscovered", mapOf("peers" to peersList))
    }
    
    private fun handleConnectionChanged(intent: Intent) {
        val networkInfo = intent.getParcelableExtra<android.net.NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
        val isConnected = networkInfo?.isConnected == true
        
        if (isConnected) {
            wifiP2pManager?.requestConnectionInfo(channel) { info: WifiP2pInfo? ->
                connectionInfo = info
                val isGroupOwner = info?.isGroupOwner == true
                val groupOwnerAddress = info?.groupOwnerAddress?.hostAddress
                
                notifyFlutter("connectionStateChanged", mapOf(
                    "isConnected" to true,
                    "isGroupOwner" to isGroupOwner,
                    "groupOwnerAddress" to (groupOwnerAddress ?: "")
                ))
            }
        } else {
            connectionInfo = null
            notifyFlutter("connectionStateChanged", mapOf("isConnected" to false))
        }
    }
    
    // Called internally when peer events happen — pushes to Flutter
    private fun notifyFlutter(method: String, args: Map<String, Any>) {
        eventChannel.invokeMethod(method, args)
    }
    
    // Clean up resources
    fun cleanup() {
        context.unregisterReceiver(receiver)
    }
}