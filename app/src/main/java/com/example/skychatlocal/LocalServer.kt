package com.example.skychatlocal

import android.content.Context
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoWSD
import java.io.IOException

class LocalServer(
    private val context: Context,
    port: Int,
    private val listener: WebServerListener
) : NanoWSD(port) {

    // Lista clienților WebSocket conectați
    private val webSocketSockets = mutableListOf<WebSocket>()

    // FĂRĂ INIT BLOCK, FĂRĂ CERTIFICAT, FĂRĂ SSL

    override fun openWebSocket(handshake: IHTTPSession): WebSocket {
        return AirChatWebSocket(this, handshake)
    }

    override fun serveHttp(session: IHTTPSession): Response {
        var uri = session.uri
        if (uri == "/") uri = "/index.html"
        val assetPath = uri.trimStart('/')

        return try {
            val mimeType = when {
                uri.endsWith(".css") -> "text/css"
                uri.endsWith(".js") -> "application/javascript"
                uri.endsWith(".html") -> "text/html"
                else -> "text/plain"
            }

            val inputStream = context.assets.open(assetPath)
            newChunkedResponse(Response.Status.OK, mimeType, inputStream)
        } catch (e: IOException) {
            newFixedLengthResponse(Response.Status.NOT_FOUND, NanoHTTPD.MIME_PLAINTEXT, "File not found")
        }
    }

    fun broadcastToAll(message: String) {
        val deadSockets = mutableListOf<WebSocket>()
        synchronized(webSocketSockets) {
            for (ws in webSocketSockets) {
                try {
                    if (ws.isOpen) ws.send(message) else deadSockets.add(ws)
                } catch (e: Exception) {
                    deadSockets.add(ws)
                }
            }
            webSocketSockets.removeAll(deadSockets)
        }
    }

    private class AirChatWebSocket(
        private val server: LocalServer,
        handshake: IHTTPSession
    ) : WebSocket(handshake) {

        override fun onOpen() {
            synchronized(server.webSocketSockets) { server.webSocketSockets.add(this) }
        }

        override fun onClose(code: WebSocketFrame.CloseCode?, reason: String?, initiatedByRemote: Boolean) {
            synchronized(server.webSocketSockets) { server.webSocketSockets.remove(this) }
            if (server.webSocketSockets.isEmpty()) {
                server.listener.onClientDisconnected()
            }
        }

        override fun onMessage(message: WebSocketFrame) {
            val text = message.textPayload
            server.listener.onMessageFromWeb(text)
            server.broadcastToAll(text)
        }

        override fun onPong(pong: WebSocketFrame?) {}
        override fun onException(exception: IOException?) {}
    }
}