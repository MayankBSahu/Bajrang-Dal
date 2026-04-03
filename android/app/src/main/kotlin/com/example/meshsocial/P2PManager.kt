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
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class P2PManager(
    private val context: Context,
    messenger: BinaryMessenger
) {
    private val TAG = "MeshSocial-P2PManager"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val gossipExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    // Wi-Fi Direct often emits multiple connection change broadcasts while negotiating.
    // Debounce groupFormed=false so we do not close the TCP server or client prematurely.
    @Volatile
    private var lastGroupFormedAtMs: Long = 0L
    private val groupFormDebounceMs = 1500L

    @Volatile
    private var pendingStopToken: Long = 0L

    @Volatile
    private var transportStartPending = false

    @Volatile
    private var wifiGroupFormed = false

    private val socketServer = SocketServer(
        onPayloadReceived = { peerId, payload ->
            handleGossipPayloadFromPeer(peerId, payload)
        },
        onPeerConnected = { peerId, peerCount ->
            transportStartPending = false
            notifyTransportState(peerCount)
            notifyFlutterMain(
                "gossipTransportReady",
                mapOf("peerId" to peerId, "peerCount" to peerCount)
            )
            if (!isGroupOwnerTransport()) {
                scheduleHelloForPeers(listOf(peerId))
            }
        },
        onPeerDisconnected = { peerId, reason, peerCount ->
            transportStartPending = false
            notifyTransportState(peerCount)
            if (!reason.isNullOrBlank()) {
                notifyFlutterMain(
                    "meshDebugError",
                    mapOf("message" to "Mesh peer $peerId disconnected: $reason")
                )
            }
        },
        onTransportError = { err ->
            transportStartPending = false
            notifyFlutterMain("meshDebugError", mapOf("message" to err))
        }
    )

    /** Flutter UI + DB I/O; native drives gossip protocol via [GossipEngine]. */
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
                    handleConnectionChanged()
                }
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    thisDevice = intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                    notifyFlutter(
                        "thisDeviceChanged",
                        mapOf(
                            "deviceName" to (thisDevice?.deviceName ?: ""),
                            "deviceAddress" to (thisDevice?.deviceAddress ?: "")
                        )
                    )
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
        context.registerReceiver(receiver, intentFilter)
    }

    private fun hasWifiDirectDiscoveryPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.NEARBY_WIFI_DEVICES
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    fun startDiscovery(result: MethodChannel.Result) {
        val mgr = wifiP2pManager
        val ch = channel
        if (mgr == null || ch == null) {
            result.error("NO_P2P", "WiFi Direct is not available on this device", null)
            return
        }

        if (!hasWifiDirectDiscoveryPermission()) {
            result.error(
                "PERMISSION_DENIED",
                "Grant Location (Android 12 and below) or Nearby WiFi devices (Android 13+) for discovery",
                null
            )
            return
        }

        if (isDiscovering) {
            result.success(null)
            return
        }

        mgr.discoverPeers(ch, object : WifiP2pManager.ActionListener {
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
        val mgr = wifiP2pManager
        val ch = channel
        if (mgr == null || ch == null) {
            result.error("NO_P2P", "WiFi Direct is not available on this device", null)
            return
        }
        if (!hasWifiDirectDiscoveryPermission()) {
            result.error("PERMISSION_DENIED", "Missing WiFi Direct permissions", null)
            return
        }

        val addrNorm = address.trim().uppercase()
        if (addrNorm.isEmpty()) {
            result.error("BAD_ADDRESS", "Missing peer address", null)
            return
        }

        mgr.requestPeers(ch) { peerList: WifiP2pDeviceList? ->
            val fresh = peerList?.deviceList ?: emptyList()
            if (fresh.isNotEmpty()) {
                discoveredPeers.clear()
                discoveredPeers.addAll(fresh)
            }
            val device = fresh.find { it.deviceAddress.equals(addrNorm, ignoreCase = true) }
                ?: discoveredPeers.find { it.deviceAddress.equals(addrNorm, ignoreCase = true) }

            mainHandler.post {
                if (device == null) {
                    result.error(
                        "DEVICE_NOT_FOUND",
                        "This phone does not see that peer over WiFi Direct. On both phones: open Nearby, tap Scan, wait until the other device appears, then tap Connect.",
                        null
                    )
                    return@post
                }

                val config = WifiP2pConfig().apply {
                    deviceAddress = device.deviceAddress
                    wps.setup = WpsInfo.PBC
                }

                mgr.connect(ch, config, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.d(TAG, "Connection to ${device.deviceAddress} initiated")
                        mainHandler.post { result.success(null) }
                    }

                    override fun onFailure(reason: Int) {
                        val msg = connectFailureMessage(reason)
                        Log.e(TAG, "connect failed reason=$reason: $msg")
                        mainHandler.post {
                            result.error("CONNECTION_FAILED", msg, mapOf("reason" to reason))
                        }
                    }
                })
            }
        }
    }

    private fun connectFailureMessage(reason: Int): String = when (reason) {
        WifiP2pManager.P2P_UNSUPPORTED ->
            "WiFi Direct is not available. Turn WiFi on and try again."
        WifiP2pManager.BUSY ->
            "WiFi Direct is busy. Disconnect any existing link, wait a few seconds, then try again on both phones."
        else ->
            "Could not connect (error $reason). Try scanning again on both phones and accept the WiFi Direct invite if it pops up."
    }

    fun disconnect(result: MethodChannel.Result) {
        transportStartPending = false
        socketServer.stop()
        wifiGroupFormed = false
        wifiP2pManager?.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Disconnected successfully")
                connectionInfo = null
                notifyTransportState(0)
                result.success(null)
            }

            override fun onFailure(reason: Int) {
                Log.e(TAG, "Failed to disconnect: $reason")
                result.error("DISCONNECT_FAILED", "Failed to disconnect: $reason", null)
            }
        })
    }

    fun sendGossipPayload(address: String, payload: String, result: MethodChannel.Result) {
        val targetPeerIds = resolveTargetPeerIds(address)
        if (targetPeerIds.isEmpty()) {
            result.error("NO_SOCKET", "Gossip transport is not connected", null)
            return
        }

        gossipExecutor.execute {
            try {
                sendPayloadToPeers(payload, targetPeerIds)
                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                Log.e(TAG, "sendGossipPayload failed", e)
                mainHandler.post {
                    result.error("SEND_FAILED", e.message ?: "send failed", null)
                }
            }
        }
    }

    fun getDeviceAddress(result: MethodChannel.Result) {
        result.success(thisDevice?.deviceAddress)
    }

    /** Opens system WiFi UI so the user can find WiFi Direct / pending invites (OEM-dependent). */
    fun openWifiSettings(result: MethodChannel.Result) {
        val newTask = Intent.FLAG_ACTIVITY_NEW_TASK
        val candidates = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                add(Intent(Settings.Panel.ACTION_WIFI).addFlags(newTask))
            }
            add(Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(newTask))
        }
        for (intent in candidates) {
            try {
                context.startActivity(intent)
                result.success(null)
                return
            } catch (_: Exception) {
                // try next
            }
        }
        result.error("INTENT_FAILED", "Could not open WiFi settings", null)
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

    private fun handleConnectionChanged() {
        wifiP2pManager?.requestConnectionInfo(channel) { info: WifiP2pInfo? ->
            val groupFormed = info?.groupFormed == true
            val now = System.currentTimeMillis()

            if (!groupFormed) {
                val elapsed = now - lastGroupFormedAtMs
                val delay = maxOf(0L, groupFormDebounceMs - elapsed)
                val myToken = ++pendingStopToken

                mainHandler.postDelayed({
                    if (pendingStopToken != myToken) return@postDelayed

                    val elapsed2 = System.currentTimeMillis() - lastGroupFormedAtMs
                    if (elapsed2 >= groupFormDebounceMs) {
                        transportStartPending = false
                        wifiGroupFormed = false
                        connectionInfo = null
                        socketServer.stop()
                        notifyTransportState(0)
                    }
                }, delay)
                return@requestConnectionInfo
            }

            lastGroupFormedAtMs = now
            pendingStopToken++
            wifiGroupFormed = true
            connectionInfo = info
            notifyTransportState(socketServer.getConnectionCount())

            if (!socketServer.isRunning() && !transportStartPending) {
                transportStartPending = true
                startGossipTransport(
                    isGroupOwner = info?.isGroupOwner == true,
                    groupOwnerHost = info?.groupOwnerAddress?.hostAddress.orEmpty()
                )
            }
        }
    }

    private fun startGossipTransport(isGroupOwner: Boolean, groupOwnerHost: String) {
        if (isGroupOwner) {
            socketServer.startAsGroupOwner()
            return
        }

        if (groupOwnerHost.isNotEmpty()) {
            socketServer.startAsClient(groupOwnerHost)
        } else {
            transportStartPending = false
            Log.e(TAG, "Group owner address missing")
            notifyFlutterMain("meshDebugError", mapOf("message" to "Group owner address missing"))
        }
    }

    /**
     * Flutter calls this after creating a post while the gossip socket is up.
     */
    fun pushGossipSync(result: MethodChannel.Result) {
        val targetPeerIds = resolveTargetPeerIds(address = "")
        if (targetPeerIds.isEmpty()) {
            result.error("NO_SOCKET", "No active mesh link. Connect to a peer on the Nearby tab first.", null)
            return
        }

        scheduleHelloForPeers(
            peerIds = targetPeerIds,
            onSuccess = { mainHandler.post { result.success(null) } },
            onFailure = { error ->
                mainHandler.post { result.error("PUSH_FAILED", error.message, null) }
            }
        )
    }

    /** Ground test: send a raw debug marker over the open TCP gossip socket. */
    fun sendDebugPing(payload: String, result: MethodChannel.Result) {
        val targetPeerIds = resolveTargetPeerIds(address = "")
        if (targetPeerIds.isEmpty()) {
            result.error("NO_SOCKET", "No active mesh link.", null)
            return
        }

        gossipExecutor.execute {
            try {
                sendPayloadToPeers(payload, targetPeerIds)
                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                Log.e(TAG, "sendDebugPing failed", e)
                mainHandler.post { result.error("DEBUG_PING_FAILED", e.message, null) }
            }
        }
    }

    private fun handleGossipPayloadFromPeer(sourcePeerId: String, payload: String) {
        if (payload.startsWith("DEBUG_PING|")) {
            notifyFlutter("meshDebugPingReceived", mapOf("payload" to payload))
            return
        }

        when (GossipEngine.getEnvelopeType(payload)) {
            "hello" -> handleHelloEnvelope(sourcePeerId, payload)
            "sync" -> handleSyncEnvelope(sourcePeerId, payload)
        }
    }

    private fun handleHelloEnvelope(sourcePeerId: String, payload: String) {
        val theirIds = GossipEngine.parseHelloIds(payload)
        mainHandler.post {
            eventChannel.invokeMethod(
                "gossipProcessHello",
                mapOf("theirIds" to theirIds),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        gossipExecutor.execute {
                            val map = result as? Map<*, *> ?: return@execute
                            val peerId = map["peerId"] as? String ?: return@execute
                            val missingPosts = map["missingPosts"]
                            val requestIds = map["requestIds"]
                            val syncEnv = GossipEngine.buildSyncEnvelope(peerId, missingPosts, requestIds)
                            try {
                                socketServer.sendPayloadSync(syncEnv, sourcePeerId)
                                val count = (missingPosts as? List<*>)?.size ?: 0
                                notifyFlutterMain("meshDebugPushSent", mapOf("postCount" to count))
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed sending SYNC to $sourcePeerId", e)
                            }
                        }
                    }

                    override fun error(code: String, msg: String?, details: Any?) {}

                    override fun notImplemented() {}
                }
            )
        }
    }

    private fun handleSyncEnvelope(sourcePeerId: String, payload: String) {
        mainHandler.post {
            eventChannel.invokeMethod("getPeerId", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    gossipExecutor.execute {
                        val localPeerId = result as? String ?: return@execute
                        val parsedPosts = GossipEngine.parseSyncPosts(payload, localPeerId)
                        val requestIds = GossipEngine.parseSyncRequestIds(payload)

                        if (parsedPosts.isNotEmpty()) {
                            applyIncomingPosts(sourcePeerId, parsedPosts)
                        }

                        if (requestIds.isNotEmpty()) {
                            fulfillSyncRequests(sourcePeerId, requestIds)
                        }
                    }
                }

                override fun error(code: String, msg: String?, details: Any?) {}

                override fun notImplemented() {}
            })
        }
    }

    private fun applyIncomingPosts(sourcePeerId: String, parsedPosts: List<Map<String, Any?>>) {
        mainHandler.post {
            eventChannel.invokeMethod(
                "gossipApplyPosts",
                mapOf("posts" to parsedPosts),
                object : MethodChannel.Result {
                    override fun success(res: Any?) {
                        notifyFlutterMain(
                            "meshDebugApplied",
                            mapOf("mergedCount" to parsedPosts.size, "needsAck" to false)
                        )
                        if (isGroupOwnerTransport()) {
                            relayHelloToOtherPeers(sourcePeerId)
                        }
                    }

                    override fun error(code: String, msg: String?, details: Any?) {}

                    override fun notImplemented() {}
                }
            )
        }
    }

    private fun fulfillSyncRequests(sourcePeerId: String, requestIds: List<String>) {
        mainHandler.post {
            eventChannel.invokeMethod(
                "gossipProcessSyncRequests",
                mapOf("requestIds" to requestIds),
                object : MethodChannel.Result {
                    override fun success(reqResult: Any?) {
                        gossipExecutor.execute {
                            val map = reqResult as? Map<*, *> ?: return@execute
                            val peerId = map["peerId"] as? String ?: return@execute
                            val missingPosts = map["missingPosts"]
                            val reqEnv = GossipEngine.buildSyncEnvelope(peerId, missingPosts, null)
                            try {
                                socketServer.sendPayloadSync(reqEnv, sourcePeerId)
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed responding to sync request from $sourcePeerId", e)
                            }
                        }
                    }

                    override fun error(code: String, msg: String?, details: Any?) {}

                    override fun notImplemented() {}
                }
            )
        }
    }

    private fun relayHelloToOtherPeers(sourcePeerId: String) {
        val targetPeerIds = socketServer.getConnectedPeerIds().filterNot { it == sourcePeerId }
        if (targetPeerIds.isEmpty()) return
        scheduleHelloForPeers(targetPeerIds)
    }

    private fun scheduleHelloForPeers(
        peerIds: List<String>,
        onSuccess: (() -> Unit)? = null,
        onFailure: ((Exception) -> Unit)? = null
    ) {
        val distinctPeerIds = peerIds.distinct()
        if (distinctPeerIds.isEmpty()) {
            onSuccess?.invoke()
            return
        }

        mainHandler.post {
            eventChannel.invokeMethod("getGossipHelloExport", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    gossipExecutor.execute {
                        val map = result as? Map<*, *> ?: run {
                            onFailure?.invoke(IllegalStateException("HELLO export missing"))
                            return@execute
                        }
                        val peerId = map["peerId"] as? String ?: run {
                            onFailure?.invoke(IllegalStateException("Local peer id missing"))
                            return@execute
                        }
                        val hello = GossipEngine.buildHelloEnvelope(peerId, map["postIds"])
                        try {
                            val sentCount = sendPayloadToPeers(hello, distinctPeerIds)
                            notifyFlutterMain("meshDebugPushSent", mapOf("postCount" to 0))
                            if (sentCount == 0) {
                                onFailure?.invoke(IllegalStateException("No mesh peers accepted the HELLO"))
                            } else {
                                onSuccess?.invoke()
                            }
                        } catch (e: Exception) {
                            onFailure?.invoke(e)
                        }
                    }
                }

                override fun error(code: String, msg: String?, details: Any?) {
                    onFailure?.invoke(IllegalStateException(msg ?: code))
                }

                override fun notImplemented() {
                    onFailure?.invoke(IllegalStateException("getGossipHelloExport not implemented"))
                }
            })
        }
    }

    private fun sendPayloadToPeers(payload: String, peerIds: List<String>): Int {
        var sentCount = 0
        var lastError: Exception? = null

        peerIds.forEach { peerId ->
            try {
                socketServer.sendPayloadSync(payload, peerId)
                sentCount += 1
            } catch (e: Exception) {
                lastError = e
                Log.e(TAG, "Failed sending payload to $peerId", e)
            }
        }

        if (sentCount == 0 && lastError != null) {
            throw lastError as Exception
        }

        return sentCount
    }

    private fun resolveTargetPeerIds(address: String): List<String> {
        val connectedPeerIds = socketServer.getConnectedPeerIds()
        if (connectedPeerIds.isEmpty()) return emptyList()

        val trimmedAddress = address.trim()
        if (trimmedAddress.isNotEmpty()) {
            return connectedPeerIds.filter { it == trimmedAddress }
        }

        return if (isGroupOwnerTransport()) {
            connectedPeerIds
        } else {
            connectedPeerIds.take(1)
        }
    }

    private fun isGroupOwnerTransport(): Boolean {
        return connectionInfo?.isGroupOwner == true
    }

    private fun notifyTransportState(peerCount: Int) {
        notifyFlutterMain(
            "connectionStateChanged",
            mapOf(
                "isConnected" to (peerCount > 0),
                "isGroupOwner" to isGroupOwnerTransport(),
                "groupOwnerAddress" to (connectionInfo?.groupOwnerAddress?.hostAddress ?: ""),
                "peerCount" to peerCount,
                "groupFormed" to wifiGroupFormed
            )
        )
    }

    /** Always hop to main: Flutter method channel is unsafe from binder / WiFi P2P threads. */
    private fun notifyFlutterMain(method: String, args: Map<String, Any>) {
        notifyFlutter(method, args)
    }

    // Called internally when peer events happen; pushes to Flutter on the main thread only.
    private fun notifyFlutter(method: String, args: Map<String, Any>) {
        mainHandler.post {
            try {
                eventChannel.invokeMethod(method, args)
            } catch (e: Exception) {
                Log.e(TAG, "notifyFlutter $method failed", e)
            }
        }
    }

    // Clean up resources
    fun cleanup() {
        transportStartPending = false
        socketServer.stop()
        context.unregisterReceiver(receiver)
    }
}
