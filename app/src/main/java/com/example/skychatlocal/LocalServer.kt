package com.example.skychatlocal

import android.content.Context
import android.util.Log
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoWSD
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import java.security.KeyStore
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext

class LocalServer(private val context: Context, port: Int) : NanoWSD(port) {

    private val connections = CopyOnWriteArrayList<WebSocket>()
    private val TAG = "SkyChatServer"



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

            // ORICE URL necunoscut -> trimitem index.html (pagina de login)
            return try {
                val stream = context.assets.open("index.html")
                NanoHTTPD.newChunkedResponse(
                    Response.Status.OK,
                    "text/html",
                    stream
                )
            } catch (e2: IOException) {
                NanoHTTPD.newFixedLengthResponse(
                    Response.Status.NOT_FOUND,
                    NanoHTTPD.MIME_PLAINTEXT,
                    "404 Not Found"
                )
            }
        }
    }

    // Trimite către toți clienții numărul curent de conexiuni
    private fun broadcastUserCount() {
        val count = connections.size
        val json = """{"type":"user_count","count":$count}"""
        for (conn in connections) {
            try {
                conn.send(json)
            } catch (e: Exception) {
                Log.e(TAG, "Eroare trimitere user_count", e)
            }
        }
    }

    override fun openWebSocket(handshake: IHTTPSession): WebSocket {
        return ChatWebSocket(handshake)
    }

    private inner class ChatWebSocket(handshakeRequest: IHTTPSession) :
        WebSocket(handshakeRequest) {

        override fun onOpen() {
            connections.add(this)
            Log.d(TAG, "Utilizator conectat. Total: ${connections.size}")
            this@LocalServer.broadcastUserCount()
        }

        override fun onClose(
            code: WebSocketFrame.CloseCode?,
            reason: String?,
            initiatedByRemote: Boolean
        ) {
            connections.remove(this)
            Log.d(TAG, "Utilizator deconectat.")
            this@LocalServer.broadcastUserCount()
        }

        override fun onMessage(message: WebSocketFrame) {
            val payload = message.textPayload

            // Ignorăm mesajele de tip heartbeat (ping)
            if (payload == "ping") {
                return
            }

            Log.d(TAG, "Broadcasting: $payload")

            for (conn in connections) {
                try {
                    conn.send(payload)
                } catch (e: Exception) {
                    Log.e(TAG, "Eroare trimitere mesaj", e)
                }
            }
        }

        override fun onPong(pong: WebSocketFrame?) {}

        override fun onException(exception: IOException?) {
            Log.e(TAG, "Eroare Socket", exception)
        }
    }
}