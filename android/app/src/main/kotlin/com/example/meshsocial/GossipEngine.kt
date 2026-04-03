package com.example.meshsocial

import org.json.JSONArray
import org.json.JSONObject

/**
 * Mesh gossip protocol and merge rules (Android / Kotlin). UI stays in Flutter; transport in [P2PManager].
 */
object GossipEngine {
    const val PROTOCOL_VERSION = 1
    const val MAX_HOPS = 12

    fun buildEnvelope(type: String, peerId: String, posts: Any?): String {
        val root = JSONObject()
        root.put("v", PROTOCOL_VERSION)
        root.put("type", type)
        root.put("senderId", peerId)
        root.put("posts", postsToJsonArray(posts))
        return root.toString()
    }

    fun buildSyncEnvelope(peerId: String, posts: Any?): String =
        buildEnvelope("sync", peerId, posts)

    fun buildAckEnvelope(peerId: String, posts: Any?): String =
        buildEnvelope("sync_ack", peerId, posts)

    data class ProcessResult(
        /** Post rows for Flutter to persist (snake_case keys matching SQLite). */
        val mergedPosts: List<Map<String, Any?>>,
        /** If true, send [buildAckEnvelope] after Flutter applies rows and returns fresh export. */
        val needsAck: Boolean
    )

    /**
     * @param raw incoming UTF-8 JSON frame
     * @param export map from Flutter: peerId, posts (list of maps) — used for merge rules only
     */
    fun processIncoming(raw: String, export: Map<*, *>): ProcessResult {
        val localPeerId = export["peerId"] as? String ?: return ProcessResult(emptyList(), false)
        val env = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return ProcessResult(emptyList(), false)
        }
        if (env.optInt("v") != PROTOCOL_VERSION) {
            return ProcessResult(emptyList(), false)
        }
        val type = env.optString("type")
        if (type != "sync" && type != "sync_ack") {
            return ProcessResult(emptyList(), false)
        }
        val postsArr = env.optJSONArray("posts") ?: JSONArray()
        val merged = mutableListOf<Map<String, Any?>>()
        for (i in 0 until postsArr.length()) {
            val o = postsArr.optJSONObject(i) ?: continue
            val postId = o.optString("post_id")
            if (postId.isEmpty()) continue
            val authorId = o.optString("author_id")
            val hopIn = o.optInt("hop_count", 0)
            val storedHop = if (authorId == localPeerId) hopIn else hopIn + 1
            if (storedHop > MAX_HOPS) continue
            val synced = o.opt("synced")
            val syncedInt = when (synced) {
                is Boolean -> if (synced) 1 else 0
                is Number -> synced.toInt()
                else -> o.optInt("synced", 0)
            }
            merged.add(
                mapOf(
                    "post_id" to postId,
                    "author_id" to authorId,
                    "author_name" to o.optString("author_name", "Unknown"),
                    "content" to o.optString("content", ""),
                    "created_at" to o.optString("created_at", ""),
                    "hop_count" to storedHop,
                    "synced" to syncedInt
                )
            )
        }
        val needsAck = type == "sync"
        return ProcessResult(merged, needsAck)
    }

    private fun postsToJsonArray(posts: Any?): JSONArray {
        val arr = JSONArray()
        val list = posts as? List<*> ?: return arr
        for (item in list) {
            if (item is Map<*, *>) {
                arr.put(mapToJsonObject(item))
            }
        }
        return arr
    }

    private fun mapToJsonObject(map: Map<*, *>): JSONObject {
        val o = JSONObject()
        for ((k, v) in map) {
            val key = k.toString()
            when (v) {
                is Map<*, *> -> o.put(key, mapToJsonObject(v))
                is List<*> -> o.put(key, listToJson(v))
                else -> o.put(key, v)
            }
        }
        return o
    }

    private fun listToJson(list: List<*>): JSONArray {
        val a = JSONArray()
        for (x in list) {
            when (x) {
                is Map<*, *> -> a.put(mapToJsonObject(x))
                is List<*> -> a.put(listToJson(x))
                else -> a.put(x)
            }
        }
        return a
    }
}
