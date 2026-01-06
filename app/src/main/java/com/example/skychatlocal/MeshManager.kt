package com.example.skychatlocal

import android.content.Context
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import org.json.JSONObject
import java.util.*

class MeshManager(
    private val context: Context,
    private val myName: String,
    private val onMessageReceived: (String) -> Unit,
    private val onDeviceLost: () -> Unit,
    private val onPeerFound: (String, String) -> Unit
) {
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
            val str = String(bytes)
            try {
                val json = JSONObject(str)
                val msgId = json.optString("id", "")
                if (!seenMessageIds.contains(msgId)) {
                    seenMessageIds.add(msgId)
                    onMessageReceived(str)
                    broadcast(payload, id)
                }
            } catch (e: Exception) {}
        }
        override fun onPayloadTransferUpdate(id: String, update: PayloadTransferUpdate) {}
    }

    fun sendMessage(jsonStr: String) {
        try {
            val json = JSONObject(jsonStr)
            if (!json.has("id")) json.put("id", UUID.randomUUID().toString())
            seenMessageIds.add(json.getString("id"))
            broadcast(Payload.fromBytes(json.toString().toByteArray()))
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