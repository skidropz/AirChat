package com.example.skychatlocal

import android.content.Context
import android.util.Log
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoWSD
import java.io.IOException
import java.security.KeyStore
import java.util.concurrent.CopyOnWriteArrayList
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext

class LocalServer(
    private val context: Context,
    port: Int,
    private val listener: WebServerListener? // Ascultător pentru legătura cu Mesh
) : NanoWSD(port) {

    private val connections = CopyOnWriteArrayList<WebSocket>()
    private val TAG = "SkyChatServer"

    init {
        // ACTIVARE HTTPS (SSL)
        try {
            val keystoreStream = context.assets.open("airchat.p12")
            val keystore = KeyStore.getInstance("PKCS12")
            keystore.load(keystoreStream, "123456".toCharArray())

            val keyManagerFactory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
            keyManagerFactory.init(keystore, "123456".toCharArray())

            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(keyManagerFactory.keyManagers, null, null)

            makeSecure(sslContext.serverSocketFactory, null)
            Log.d(TAG, "🔒 Server HTTPS activ")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Eroare SSL: ${e.message}")
        }
    }

    // Funcție pentru a trimite un mesaj către TOȚI clienții web conectați
    // (Folosită când primim un mesaj din Mesh de la alt Android)
    fun broadcastToAll(message: String) {
        for (conn in connections) {
            try {
                conn.send(message)
            } catch (e: Exception) {
                Log.e(TAG, "Eroare broadcast", e)
            }
        }
    }

    override fun serveHttp(session: IHTTPSession): Response {
        var uri = session.uri
        if (uri == "/" || uri.isEmpty()) uri = "/index.html"

        val assetPath = uri.removePrefix("/")

        return try {
            val mimeType = when {
                assetPath.endsWith(".html") -> "text/html"
                assetPath.endsWith(".css") -> "text/css"
                assetPath.endsWith(".js") -> "application/javascript"
                assetPath.endsWith(".png") -> "image/png"
                assetPath.endsWith(".jpg") || assetPath.endsWith(".jpeg") -> "image/jpeg"
                assetPath.endsWith(".svg") -> "image/svg+xml"
                else -> "application/octet-stream"
            }
            val stream = context.assets.open(assetPath)
            NanoHTTPD.newChunkedResponse(Response.Status.OK, mimeType, stream)
        } catch (e: IOException) {
            // Fallback la index.html pentru rute necunoscute (SPA style)
            try {
                val stream = context.assets.open("index.html")
                NanoHTTPD.newChunkedResponse(Response.Status.OK, "text/html", stream)
            } catch (e2: IOException) {
                NanoHTTPD.newFixedLengthResponse(Response.Status.NOT_FOUND, NanoHTTPD.MIME_PLAINTEXT, "404 Not Found")
            }
        }
    }

    private fun broadcastUserCount() {
        val count = connections.size
        val json = """{"type":"user_count","count":$count}"""
        broadcastToAll(json)
    }

    override fun openWebSocket(handshake: IHTTPSession): WebSocket {
        return ChatWebSocket(handshake)
    }

    private inner class ChatWebSocket(handshakeRequest: IHTTPSession) : WebSocket(handshakeRequest) {

        override fun onOpen() {
            connections.add(this)
            Log.d(TAG, "Client conectat. Total: ${connections.size}")
            broadcastUserCount()
        }

        override fun onClose(code: WebSocketFrame.CloseCode?, reason: String?, initiatedByRemote: Boolean) {
            connections.remove(this)
            Log.d(TAG, "Client deconectat.")
            broadcastUserCount()

            // Anunțăm MainActivity pentru a declanșa alarma sonoră
            listener?.onClientDisconnected()
        }

        override fun onMessage(message: WebSocketFrame) {
            val payload = message.textPayload
            if (payload == "ping") return

            // 1. Trimitem mesajul primit către Mesh (alte Android-uri)
            listener?.onMessageFromWeb(payload)

            // 2. Trimitem mesajul către toți ceilalți clienți Web conectați la noi (iPhone-uri)
            broadcastToAll(payload)
        }

        override fun onPong(pong: WebSocketFrame?) {}
        override fun onException(exception: IOException?) {
            Log.e(TAG, "Eroare Socket", exception)
        }
    }
}