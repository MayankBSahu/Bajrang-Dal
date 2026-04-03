package com.example.meshsocial

import android.util.Log
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class SocketServer(
    private val onPayloadReceived: (String, String) -> Unit,
    private val onPeerConnected: (String, Int) -> Unit,
    private val onPeerDisconnected: (String, String?, Int) -> Unit,
    private val onTransportError: (String) -> Unit
) {
    companion object {
        private const val GOSSIP_PORT = 8988
        private const val MAX_PAYLOAD_BYTES = 8 * 1024 * 1024
        private const val TAG = "MeshSocial-SocketServer"
    }

    private enum class Mode {
        GROUP_OWNER,
        CLIENT
    }

    private data class PeerConnection(
        val peerId: String,
        val socket: Socket,
        val outStream: DataOutputStream,
        val sendLock: Any = Any()
    )

    private val controlExecutor = Executors.newSingleThreadExecutor()
    private val readExecutor = Executors.newCachedThreadPool()
    private val stopped = AtomicBoolean(false)
    private val peerSequence = AtomicInteger(0)
    private val connections = ConcurrentHashMap<String, PeerConnection>()

    @Volatile
    private var mode: Mode? = null

    @Volatile
    private var serverSocket: ServerSocket? = null

    fun startAsGroupOwner() {
        mode = Mode.GROUP_OWNER
        stopped.set(false)
        controlExecutor.execute {
            closeQuietly(notifyDisconnect = false)
            try {
                val server = ServerSocket()
                server.reuseAddress = true
                server.bind(InetSocketAddress(GOSSIP_PORT))
                serverSocket = server
                Log.d(TAG, "Gossip server listening on port $GOSSIP_PORT")

                while (!stopped.get()) {
                    val client = try {
                        server.accept()
                    } catch (e: IOException) {
                        if (stopped.get()) {
                            break
                        }
                        throw e
                    }

                    if (stopped.get()) {
                        client.close()
                        break
                    }

                    client.tcpNoDelay = true
                    registerConnection(client)
                }
            } catch (e: Exception) {
                if (!stopped.get()) {
                    Log.e(TAG, "Server error", e)
                    onTransportError(e.message ?: "Server error")
                }
            }
        }
    }

    fun startAsClient(groupOwnerHost: String) {
        mode = Mode.CLIENT
        stopped.set(false)
        controlExecutor.execute {
            closeQuietly(notifyDisconnect = false)
            try {
                var socket: Socket? = null
                for (attempt in 0 until 25) {
                    if (stopped.get()) return@execute
                    try {
                        val candidate = Socket()
                        candidate.tcpNoDelay = true
                        candidate.connect(InetSocketAddress(groupOwnerHost, GOSSIP_PORT), 4000)
                        socket = candidate
                        break
                    } catch (e: Exception) {
                        Log.w(TAG, "Connect attempt ${attempt + 1} failed: ${e.message}")
                        Thread.sleep(350)
                    }
                }

                val connected = socket
                    ?: throw IOException("Client could not connect to group owner $groupOwnerHost")

                registerConnection(connected, preferredPeerId = groupOwnerHost)
            } catch (e: Exception) {
                if (!stopped.get()) {
                    Log.e(TAG, "Client error", e)
                    onTransportError(e.message ?: "Client error")
                }
            }
        }
    }

    @Throws(IOException::class)
    fun sendPayloadSync(payload: String, peerId: String? = null) {
        val bytes = payload.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_PAYLOAD_BYTES) {
            throw IOException("Payload exceeds limit")
        }

        val connection = resolveConnection(peerId)
        synchronized(connection.sendLock) {
            connection.outStream.writeInt(bytes.size)
            connection.outStream.write(bytes)
            connection.outStream.flush()
        }
    }

    fun getConnectedPeerIds(): List<String> {
        return connections.keys.toList()
    }

    fun getConnectionCount(): Int {
        return connections.size
    }

    fun isConnected(): Boolean {
        return connections.isNotEmpty()
    }

    fun isRunning(): Boolean {
        return serverSocket != null || connections.isNotEmpty()
    }

    fun stop() {
        stopped.set(true)
        closeQuietly(notifyDisconnect = false)
    }

    private fun resolveConnection(peerId: String?): PeerConnection {
        if (peerId != null) {
            return connections[peerId]
                ?: throw IOException("Peer $peerId is not connected")
        }

        return when {
            connections.isEmpty() -> throw IOException("Gossip transport is not connected")
            connections.size == 1 -> connections.values.first()
            else -> throw IOException("Multiple mesh peers connected; specify a target peer")
        }
    }

    private fun registerConnection(socket: Socket, preferredPeerId: String? = null) {
        val peerId = buildPeerId(socket, preferredPeerId)
        val connection = PeerConnection(
            peerId = peerId,
            socket = socket,
            outStream = DataOutputStream(socket.getOutputStream())
        )

        connections.put(peerId, connection)?.let { previous ->
            closeConnection(previous)
        }

        onPeerConnected(peerId, connections.size)
        readExecutor.execute { startReadLoop(connection) }
    }

    private fun buildPeerId(socket: Socket, preferredPeerId: String?): String {
        if (!preferredPeerId.isNullOrBlank() && mode == Mode.CLIENT) {
            return preferredPeerId
        }

        val host = socket.inetAddress?.hostAddress
            ?: socket.remoteSocketAddress?.toString()?.removePrefix("/")
            ?: "peer"
        val remotePort = socket.port
        val sequence = peerSequence.incrementAndGet()
        return "$host:$remotePort#$sequence"
    }

    private fun startReadLoop(connection: PeerConnection) {
        val socket = connection.socket
        val dis = DataInputStream(socket.getInputStream())
        val buf = ByteArray(MAX_PAYLOAD_BYTES)
        var disconnectReason: String? = null

        try {
            while (!stopped.get() && !socket.isClosed) {
                val len = dis.readInt()
                if (len < 0 || len > MAX_PAYLOAD_BYTES) {
                    disconnectReason = "Invalid gossip frame length: $len"
                    Log.e(TAG, disconnectReason)
                    break
                }

                dis.readFully(buf, 0, len)
                val payload = String(buf, 0, len, Charsets.UTF_8)
                onPayloadReceived(connection.peerId, payload)
            }
        } catch (e: IOException) {
            if (!stopped.get()) {
                disconnectReason = "Gossip read loop ended: ${e.message ?: "unknown"}"
                Log.d(TAG, "Peer ${connection.peerId} disconnected: $disconnectReason")
            }
        } finally {
            val removed = removeConnection(connection.peerId, disconnectReason, notifyDisconnect = !stopped.get())
            if (removed && disconnectReason != null && mode == Mode.CLIENT && !stopped.get()) {
                onTransportError(disconnectReason)
            }
        }
    }

    private fun removeConnection(
        peerId: String,
        reason: String?,
        notifyDisconnect: Boolean
    ): Boolean {
        val removed = connections.remove(peerId) ?: return false
        closeConnection(removed)
        if (notifyDisconnect) {
            onPeerDisconnected(peerId, reason, connections.size)
        }
        return true
    }

    private fun closeQuietly(notifyDisconnect: Boolean) {
        val snapshot = connections.keys.toList()
        snapshot.forEach { peerId ->
            removeConnection(peerId, reason = null, notifyDisconnect = notifyDisconnect)
        }

        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
    }

    private fun closeConnection(connection: PeerConnection) {
        try {
            connection.outStream.close()
        } catch (_: Exception) {
        }
        try {
            connection.socket.close()
        } catch (_: Exception) {
        }
    }
}
