package com.example.meshsocial

import org.json.JSONArray
import org.json.JSONObject

/**
 * Mesh gossip protocol and merge rules (Android / Kotlin). UI stays in Flutter; transport in [P2PManager].
 */
object GossipEngine {
    const val PROTOCOL_VERSION = 1
    const val MAX_HOPS = 12

    fun getEnvelopeType(raw: String): String {
        return try { JSONObject(raw).optString("type") } catch (e: Exception) { "" }
    }

    fun buildHelloEnvelope(peerId: String, postIds: Any?): String {
        val root = JSONObject()
        root.put("v", PROTOCOL_VERSION)
        root.put("type", "hello")
        root.put("senderId", peerId)
        val arr = JSONArray()
        (postIds as? List<*>)?.forEach { arr.put(it.toString()) }
        root.put("postIds", arr)
        return root.toString()
    }

    fun parseHelloIds(raw: String): List<String> {
        val list = mutableListOf<String>()
        try {
            val env = JSONObject(raw)
            val arr = env.optJSONArray("postIds") ?: return list
            for (i in 0 until arr.length()) {
                val id = arr.optString(i)
                if (id.isNotEmpty()) list.add(id)
            }
        } catch (_: Exception) {}
        return list
    }

    fun buildSyncEnvelope(peerId: String, posts: Any?, requestIds: Any? = null): String {
        val root = JSONObject()
        root.put("v", PROTOCOL_VERSION)
        root.put("type", "sync")
        root.put("senderId", peerId)
        root.put("posts", postsToJsonArray(posts))
        
        val reqArr = JSONArray()
        (requestIds as? List<*>)?.forEach { reqArr.put(it.toString()) }
        if (reqArr.length() > 0) root.put("requestIds", reqArr)
        
        return root.toString()
    }

    fun parseSyncRequestIds(raw: String): List<String> {
        val list = mutableListOf<String>()
        try {
            val env = JSONObject(raw)
            val arr = env.optJSONArray("requestIds") ?: return list
            for (i in 0 until arr.length()) {
                val id = arr.optString(i)
                if (id.isNotEmpty()) list.add(id)
            }
        } catch (_: Exception) {}
        return list
    }

    fun parseSyncPosts(raw: String, localPeerId: String): List<Map<String, Any?>> {
        val merged = mutableListOf<Map<String, Any?>>()
        try {
            val env = JSONObject(raw)
            if (env.optInt("v") != PROTOCOL_VERSION) return merged
            val postsArr = env.optJSONArray("posts") ?: return merged
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
                        "room_id" to o.optString("room_id", "general"),
                        "room_name" to o.optString("room_name", "General"),
                        "author_id" to authorId,
                        "author_name" to o.optString("author_name", "Unknown"),
                        "content" to o.optString("content", ""),
                        "created_at" to o.optString("created_at", ""),
                        "hop_count" to storedHop,
                        "synced" to syncedInt
                    )
                )
            }
        } catch (_: Exception) {}
        return merged
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
