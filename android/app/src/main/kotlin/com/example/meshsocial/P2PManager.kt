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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class P2PManager(
    private val context: Context,
    messenger: BinaryMessenger
) {
    private val TAG = "MeshSocial-P2PManager"

    companion object {
        private const val GOSSIP_PORT = 9753
        private const val MAX_PAYLOAD_BYTES = 8 * 1024 * 1024
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val gossipExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val gossipReadExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val gossipStopped = AtomicBoolean(false)

    // Wi‑Fi Direct often emits multiple connection change broadcasts while negotiating.
    // Debounce groupFormed=false so we don't close the TCP socket prematurely.
    @Volatile
    private var lastGroupFormedAtMs: Long = 0L
    private val GROUP_FORM_DEBOUNCE_MS = 1500L

    @Volatile
    private var pendingStopToken: Long = 0L

    private var gossipServerSocket: ServerSocket? = null
    private var gossipSocket: Socket? = null
    private var gossipOut: DataOutputStream? = null
    private val gossipSendLock = Any()
    
    /** Flutter UI + DB I/O; native drives gossip protocol via [GossipEngine]. */
    private val eventChannel = MethodChannel(messenger, "meshsocial/p2p")

    private val noopResult = object : MethodChannel.Result {
        override fun success(result: Any?) {}
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
        override fun notImplemented() {}
    }
    
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
                "Grant Location (Android 12 and below) or Nearby Wi‑Fi devices (Android 13+) for discovery",
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
    
    /**
     * Resolves the peer via [WifiP2pManager.requestPeers] first. Flutter’s list can stay populated
     * after Scan stops while our in-memory [discoveredPeers] was cleared — that used to make
     * Connect a silent no-op ([DEVICE_NOT_FOUND]).
     */
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
                        "This phone doesn’t see that peer over Wi‑Fi Direct. On both phones: " +
                            "open Nearby, tap Scan, wait until the other device appears, then tap Connect " +
                            "(Wi‑Fi on, within ~1–2 m).",
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
            "Wi‑Fi Direct isn’t available. Turn Wi‑Fi on and try again."
        WifiP2pManager.BUSY ->
            "Wi‑Fi Direct is busy. Disconnect any existing link, wait a few seconds, then try again on both phones."
        else ->
            "Couldn’t connect (error $reason). Try: Scan again on both phones, accept the Wi‑Fi Direct invite if it pops up, disable VPN/hotspot."
    }
    
    fun disconnect(result: MethodChannel.Result) {
        stopGossipTransport()
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
        if (gossipOut == null) {
            result.error("NO_SOCKET", "Gossip transport is not connected", null)
            return
        }
        gossipExecutor.execute {
            try {
                sendGossipPayloadInternal(payload)
                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                Log.e(TAG, "sendGossipPayload failed", e)
                mainHandler.post {
                    result.error("SEND_FAILED", e.message ?: "send failed", null)
                }
            }
        }
    }

    @Throws(IOException::class)
    private fun sendGossipPayloadInternal(payload: String) {
        val out = gossipOut ?: throw IOException("Gossip transport is not connected")
        val bytes = payload.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_PAYLOAD_BYTES) {
            throw IOException("Payload exceeds limit")
        }
        synchronized(gossipSendLock) {
            out.writeInt(bytes.size)
            out.write(bytes)
            out.flush()
        }
    }
    
    fun getDeviceAddress(result: MethodChannel.Result) {
        result.success(thisDevice?.deviceAddress)
    }

    /** Opens system Wi‑Fi UI so the user can find Wi‑Fi Direct / pending invites (OEM-dependent). */
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
        result.error("INTENT_FAILED", "Could not open Wi‑Fi settings", null)
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
        // Wi‑Fi Direct connection broadcasts can flap; avoid using NetworkInfo
        // which can temporarily report false while a group is still formed.
        wifiP2pManager?.requestConnectionInfo(channel) { info: WifiP2pInfo? ->
            val groupFormed = info?.groupFormed == true
            val now = System.currentTimeMillis()

            if (!groupFormed) {
                // Delay stopping the TCP socket so transient broadcasts don't break the mesh.
                val elapsed = now - lastGroupFormedAtMs
                val delay = maxOf(0L, GROUP_FORM_DEBOUNCE_MS - elapsed)
                val myToken = ++pendingStopToken

                mainHandler.postDelayed({
                    // If we saw groupFormed=true again, abort this stop.
                    if (pendingStopToken != myToken) return@postDelayed

                    val elapsed2 = System.currentTimeMillis() - lastGroupFormedAtMs
                    if (elapsed2 >= GROUP_FORM_DEBOUNCE_MS && gossipOut != null) {
                        stopGossipTransport()
                        connectionInfo = null
                        notifyFlutter("connectionStateChanged", mapOf("isConnected" to false))
                    }
                }, delay)
                return@requestConnectionInfo
            }

            lastGroupFormedAtMs = now
            // Cancel any pending stop.
            pendingStopToken++
            connectionInfo = info
            val isGroupOwner = info?.isGroupOwner == true
            val groupOwnerAddress = info?.groupOwnerAddress?.hostAddress ?: ""

            notifyFlutter(
                "connectionStateChanged",
                mapOf(
                    "isConnected" to true,
                    "isGroupOwner" to isGroupOwner,
                    "groupOwnerAddress" to groupOwnerAddress
                )
            )

            // Only start once; if we restart while sockets exist we may close the
            // active TCP stream and the next send will fail (Broken pipe).
            if (gossipOut == null && gossipSocket == null) {
                startGossipTransport(isGroupOwner, groupOwnerAddress)
            }
        }
    }

    private fun startGossipTransport(isGroupOwner: Boolean, groupOwnerHost: String) {
        gossipStopped.set(false)
        gossipExecutor.execute {
            try {
                closeGossipSocketsQuietly()
                if (isGroupOwner) {
                    val server = ServerSocket()
                    server.reuseAddress = true
                    server.bind(InetSocketAddress(GOSSIP_PORT))
                    gossipServerSocket = server
                    Log.d(TAG, "Gossip server listening on port $GOSSIP_PORT")
                    val client = server.accept()
                    if (gossipStopped.get()) {
                        client.close()
                        return@execute
                    }
                    gossipSocket = client
                    gossipOut = DataOutputStream(client.getOutputStream())
                    notifyFlutterMain("gossipTransportReady", emptyMap())
                    scheduleInitialGossipSync()
                    gossipReadExecutor.execute { startReadLoop(client) }
                } else {
                    if (groupOwnerHost.isEmpty()) {
                        Log.e(TAG, "Group owner address missing")
                        return@execute
                    }
                    var socket: Socket? = null
                    for (attempt in 0 until 25) {
                        if (gossipStopped.get()) return@execute
                        try {
                            val s = Socket()
                            s.tcpNoDelay = true
                            s.connect(InetSocketAddress(groupOwnerHost, GOSSIP_PORT), 4000)
                            socket = s
                            break
                        } catch (e: Exception) {
                            Log.w(TAG, "Connect attempt ${attempt + 1} failed: ${e.message}")
                            Thread.sleep(350)
                        }
                    }
                    val connected = socket ?: run {
                        Log.e(TAG, "Client could not connect to group owner $groupOwnerHost")
                        return@execute
                    }
                    gossipSocket = connected
                    gossipOut = DataOutputStream(connected.getOutputStream())
                    notifyFlutterMain("gossipTransportReady", emptyMap())
                    scheduleInitialGossipSync()
                    gossipReadExecutor.execute { startReadLoop(connected) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Gossip transport error", e)
            }
        }
    }

    private fun startReadLoop(socket: Socket) {
        val dis = DataInputStream(socket.getInputStream())
        val buf = ByteArray(MAX_PAYLOAD_BYTES)
        while (!gossipStopped.get() && !socket.isClosed) {
            try {
                val len = dis.readInt()
                if (len < 0 || len > MAX_PAYLOAD_BYTES) {
                    Log.e(TAG, "Invalid gossip frame length: $len")
                    break
                }
                dis.readFully(buf, 0, len)
                val payload = String(buf, 0, len, Charsets.UTF_8)
                handleGossipPayloadFromPeer(payload)
            } catch (e: IOException) {
                if (!gossipStopped.get()) {
                    Log.d(TAG, "Gossip read loop ended: ${e.message}")
                    notifyFlutterMain(
                        "meshDebugError",
                        mapOf("message" to ("Gossip read loop ended: " + (e.message ?: "unknown")))
                    )
                }
                break
            }
        }
    }

    private fun stopGossipTransport() {
        gossipStopped.set(true)
        closeGossipSocketsQuietly()
    }

    private fun closeGossipSocketsQuietly() {
        try {
            gossipOut = null
            gossipSocket?.close()
        } catch (_: Exception) { }
        gossipSocket = null
        try {
            gossipServerSocket?.close()
        } catch (_: Exception) { }
        gossipServerSocket = null
    }

    /** Always hop to main: Flutter method channel is unsafe from binder / Wi‑Fi P2P threads. */
    private fun notifyFlutterMain(method: String, args: Map<String, Any>) {
        notifyFlutter(method, args)
    }

    private fun scheduleInitialGossipSync() {
        mainHandler.post {
            eventChannel.invokeMethod("getGossipExport", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    gossipExecutor.execute {
                        val err = sendSyncFromExport(result)
                        if (err != null) Log.e(TAG, "initial gossip sync failed", err)
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "getGossipExport failed: $errorMessage")
                }

                override fun notImplemented() {
                    Log.e(TAG, "getGossipExport not implemented in Dart")
                }
            })
        }
    }

    /**
     * Flutter calls this after creating a post while the gossip socket is up.
     * Without it, only the transport-ready snapshot was exchanged — new posts never reached the peer.
     */
    fun pushGossipSync(result: MethodChannel.Result) {
        if (gossipOut == null) {
            result.error(
                "NO_SOCKET",
                "No active mesh link. Connect to a peer on the Nearby tab first.",
                null
            )
            return
        }
        mainHandler.post {
            eventChannel.invokeMethod("getGossipExport", null, object : MethodChannel.Result {
                override fun success(export: Any?) {
                    gossipExecutor.execute {
                        val err = sendSyncFromExport(export)
                        mainHandler.post {
                            if (err == null) result.success(null)
                            else result.error("PUSH_FAILED", err.message ?: "push failed", null)
                        }
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    mainHandler.post {
                        result.error(errorCode, errorMessage, errorDetails)
                    }
                }

                override fun notImplemented() {
                    mainHandler.post { result.notImplemented() }
                }
            })
        }
    }

    /** Ground test: send a raw debug marker over the open TCP gossip socket. */
    fun sendDebugPing(payload: String, result: MethodChannel.Result) {
        if (gossipOut == null) {
            result.error(
                "NO_SOCKET",
                "No active mesh link. Connect to a peer on the Nearby tab first.",
                null
            )
            return
        }
        gossipExecutor.execute {
            try {
                sendGossipPayloadInternal(payload)
                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                Log.e(TAG, "sendDebugPing failed", e)
                mainHandler.post { result.error("DEBUG_PING_FAILED", e.message, null) }
            }
        }
    }

    /** Build and send a sync frame from Flutter’s export; null on success. */
    private fun sendSyncFromExport(export: Any?): Exception? {
        val map = export as? Map<*, *> ?: return Exception("Missing export")
        val peerId = map["peerId"] as? String ?: return Exception("Missing peer id")
        if (peerId.isEmpty()) return Exception("Empty peer id")
        return try {
            val posts = map["posts"]
            val postCount = (posts as? List<*>)?.size ?: 0
            val payload = GossipEngine.buildSyncEnvelope(peerId, map["posts"])
            sendGossipPayloadInternal(payload)
            notifyFlutterMain(
                "meshDebugPushSent",
                mapOf("postCount" to postCount)
            )
            mainHandler.post {
                eventChannel.invokeMethod(
                    "gossipMarkOwnSynced",
                    mapOf("peerId" to peerId),
                    noopResult
                )
            }
            null
        } catch (e: Exception) {
            e
        }
    }

    private fun handleGossipPayloadFromPeer(payload: String) {
        if (payload.startsWith("DEBUG_PING|")) {
            notifyFlutter("meshDebugPingReceived", mapOf("payload" to payload))
            return
        }

        mainHandler.post {
            eventChannel.invokeMethod("getGossipExport", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    gossipExecutor.execute {
                        val export = result as? Map<*, *> ?: return@execute
                        val processed = GossipEngine.processIncoming(payload, export)
                        mainHandler.post {
                            eventChannel.invokeMethod(
                                "gossipApplyPosts",
                                mapOf("posts" to processed.mergedPosts),
                                object : MethodChannel.Result {
                                    override fun success(applyResult: Any?) {
                                        gossipExecutor.execute {
                                            notifyFlutterMain(
                                                "meshDebugApplied",
                                                mapOf(
                                                    "mergedCount" to processed.mergedPosts.size,
                                                    "needsAck" to processed.needsAck
                                                )
                                            )
                                            if (!processed.needsAck) return@execute
                                            val fresh = applyResult as? Map<*, *> ?: return@execute
                                            val peerId = fresh["peerId"] as? String ?: return@execute
                                            try {
                                                val ack = GossipEngine.buildAckEnvelope(peerId, fresh["posts"])
                                                sendGossipPayloadInternal(ack)
                                                mainHandler.post {
                                                    eventChannel.invokeMethod(
                                                        "gossipMarkOwnSynced",
                                                        mapOf("peerId" to peerId),
                                                        noopResult
                                                    )
                                                }
                                            } catch (e: Exception) {
                                                Log.e(TAG, "sync_ack send failed", e)
                                            }
                                        }
                                    }

                                    override fun error(
                                        errorCode: String,
                                        errorMessage: String?,
                                        errorDetails: Any?
                                    ) {
                                    }

                                    override fun notImplemented() {}
                                }
                            )
                        }
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

                override fun notImplemented() {}
            })
        }
    }
    
    // Called internally when peer events happen — pushes to Flutter (main thread only).
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
        stopGossipTransport()
        context.unregisterReceiver(receiver)
    }
}