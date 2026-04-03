package com.example.meshsocial

import android.util.Log
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class SocketServer(
    private val onPayloadReceived: (String) -> Unit,
    private val onTransportReady: () -> Unit,
    private val onTransportError: (String) -> Unit
) {
    companion object {
        private const val GOSSIP_PORT = 8988
        private const val MAX_PAYLOAD_BYTES = 8 * 1024 * 1024
        private const val TAG = "MeshSocial-SocketServer"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val readExecutor = Executors.newSingleThreadExecutor()
    private val stopped = AtomicBoolean(false)

    private var serverSocket: ServerSocket? = null
    private var activeSocket: Socket? = null
    private var outStream: DataOutputStream? = null
    private val sendLock = Any()

    fun startAsGroupOwner() {
        stopped.set(false)
        executor.execute {
            closeQuietly()
            try {
                val server = ServerSocket()
                server.reuseAddress = true
                server.bind(InetSocketAddress(GOSSIP_PORT))
                serverSocket = server
                Log.d(TAG, "Gossip server listening on port $GOSSIP_PORT")
                val client = server.accept()
                if (stopped.get()) {
                    client.close()
                    return@execute
                }
                activeSocket = client
                outStream = DataOutputStream(client.getOutputStream())
                onTransportReady()
                readExecutor.execute { startReadLoop(client) }
            } catch (e: Exception) {
                if (!stopped.get()) {
                    Log.e(TAG, "Server error", e)
                    onTransportError(e.message ?: "Server error")
                }
            }
        }
    }

    fun startAsClient(groupOwnerHost: String) {
        stopped.set(false)
        executor.execute {
            closeQuietly()
            try {
                var socket: Socket? = null
                for (attempt in 0 until 25) {
                    if (stopped.get()) return@execute
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
                val connected = socket ?: throw IOException("Client could not connect to group owner $groupOwnerHost")
                activeSocket = connected
                outStream = DataOutputStream(connected.getOutputStream())
                onTransportReady()
                readExecutor.execute { startReadLoop(connected) }
            } catch (e: Exception) {
                if (!stopped.get()) {
                    Log.e(TAG, "Client error", e)
                    onTransportError(e.message ?: "Client error")
                }
            }
        }
    }

    private fun startReadLoop(socket: Socket) {
        val dis = DataInputStream(socket.getInputStream())
        val buf = ByteArray(MAX_PAYLOAD_BYTES)
        while (!stopped.get() && !socket.isClosed) {
            try {
                val len = dis.readInt()
                if (len < 0 || len > MAX_PAYLOAD_BYTES) {
                    Log.e(TAG, "Invalid gossip frame length: $len")
                    break
                }
                dis.readFully(buf, 0, len)
                val payload = String(buf, 0, len, Charsets.UTF_8)
                onPayloadReceived(payload)
            } catch (e: IOException) {
                if (!stopped.get()) {
                    Log.d(TAG, "Gossip read loop ended: ${e.message}")
                    onTransportError("Gossip read loop ended: " + (e.message ?: "unknown"))
                }
                break
            }
        }
    }

    @Throws(IOException::class)
    fun sendPayloadSync(payload: String) {
        val out = outStream ?: throw IOException("Gossip transport is not connected")
        val bytes = payload.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_PAYLOAD_BYTES) {
            throw IOException("Payload exceeds limit")
        }
        synchronized(sendLock) {
            out.writeInt(bytes.size)
            out.write(bytes)
            out.flush()
        }
    }

    fun isConnected(): Boolean {
        return outStream != null && activeSocket?.isClosed == false
    }

    fun stop() {
        stopped.set(true)
        closeQuietly()
    }

    private fun closeQuietly() {
        try {
            outStream = null
            activeSocket?.close()
        } catch (_: Exception) {}
        activeSocket = null
        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        serverSocket = null
    }
}
