package com.example.skychatlocal

import android.content.Context
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import org.json.JSONObject
import java.security.SecureRandom
import java.util.*
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class MeshManager(
    private val context: Context,
    private val myName: String,
    private val base64RoomKey: String,
    private val onMessageReceived: (String) -> Unit,
    private val onDeviceLost: () -> Unit,
    private val onPeerFound: (String, String) -> Unit
) {
    private val secretKey = SecretKeySpec(android.util.Base64.decode(base64RoomKey, android.util.Base64.URL_SAFE), "AES")

    private fun encrypt(data: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = ByteArray(12)
        SecureRandom().nextBytes(iv)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
        val ciphertext = cipher.doFinal(data)
        return iv + ciphertext
    }

    private fun decrypt(data: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = data.copyOfRange(0, 12)
        val ciphertext = data.copyOfRange(12, data.size)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
        return cipher.doFinal(ciphertext)
    }

    private val client = Nearby.getConnectionsClient(context)
    private val STRATEGY = Strategy.P2P_CLUSTER
    private val SERVICE_ID = "com.skidropz.airchat.MESH"
    private val connectedEndpoints = mutableSetOf<String>()
    private val seenMessageIds = mutableSetOf<String>()

    fun start() {
        stop()
        startAdvertising()
        startDiscovery()
    }

    private fun startAdvertising() {
        val options = AdvertisingOptions.Builder().setStrategy(STRATEGY).build()
        client.startAdvertising(myName, SERVICE_ID, connectionLifecycleCallback, options)
    }

    private fun startDiscovery() {
        val options = DiscoveryOptions.Builder().setStrategy(STRATEGY).build()
        client.startDiscovery(SERVICE_ID, endpointDiscoveryCallback, options)
    }

    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(id: String, info: DiscoveredEndpointInfo) {
            onPeerFound(id, info.endpointName)
        }
        override fun onEndpointLost(id: String) {}
    }

    fun connectToPeer(id: String) {
        client.requestConnection(myName, id, connectionLifecycleCallback)
    }

    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(id: String, info: ConnectionInfo) {
            client.acceptConnection(id, payloadCallback)
        }
        override fun onConnectionResult(id: String, res: ConnectionResolution) {
            if (res.status.isSuccess) connectedEndpoints.add(id) else onDeviceLost()
        }
        override fun onDisconnected(id: String) {
            connectedEndpoints.remove(id)
            onDeviceLost()
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(id: String, payload: Payload) {
            val bytes = payload.asBytes() ?: return
            try {
                val decryptedBytes = decrypt(bytes)
                val str = String(decryptedBytes)
                val json = JSONObject(str)
                val msgId = json.optString("id", "")
                if (!seenMessageIds.contains(msgId)) {
                    seenMessageIds.add(msgId)
                    onMessageReceived(str)
                    broadcast(payload, id) // Broadcast same encrypted payload to others
                }
            } catch (e: Exception) {
                // If decryption fails, ignore
            }
        }
        override fun onPayloadTransferUpdate(id: String, update: PayloadTransferUpdate) {}
    }

    fun sendMessage(jsonStr: String) {
        try {
            val json = JSONObject(jsonStr)
            if (!json.has("id")) json.put("id", UUID.randomUUID().toString())
            seenMessageIds.add(json.getString("id"))
            val encryptedBytes = encrypt(json.toString().toByteArray())
            broadcast(Payload.fromBytes(encryptedBytes))
        } catch (e: Exception) {}
    }

    private fun broadcast(payload: Payload, excludeId: String? = null) {
        val targets = connectedEndpoints.filter { it != excludeId }
        if (targets.isNotEmpty()) client.sendPayload(targets, payload)
    }

    fun stop() {
        client.stopAdvertising()
        client.stopDiscovery()
        client.stopAllEndpoints()
        connectedEndpoints.clear()
        seenMessageIds.clear()
    }
}