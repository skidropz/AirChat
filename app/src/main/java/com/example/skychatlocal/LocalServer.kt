package com.example.skychatlocal

import android.content.Context
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoWSD
import java.io.IOException
import java.util.LinkedList

class LocalServer(
    private val context: Context,
    port: Int,
    private val listener: WebServerListener
) : NanoWSD(port) {

    // Lista clienților WebSocket conectați
    private val webSocketSockets = mutableListOf<WebSocket>()

    // --- ISTORIC MESAJE ---
    // Păstrăm ultimele 50 de mesaje sub formă de JSON String
    private val messageHistory = LinkedList<String>()
    private val MAX_HISTORY = 50

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
            newFixedLengthResponse(Response.Status.NOT_FOUND, NanoHTTPD.MIME_PLAINTEXT, "Nu s-a găsit fișierul!")
        }
    }

    // Această funcție trimite mesajul tuturor ȘI îl salvează în istoric
    fun broadcastToAll(message: String) {
        // 1. Salvăm în istoric
        synchronized(messageHistory) {
            if (messageHistory.size >= MAX_HISTORY) {
                messageHistory.removeFirst() // Ștergem cel mai vechi mesaj dacă am depășit limita
            }
            messageHistory.add(message)
        }

        // 2. Trimitem către toți clienții conectați
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

            // --- SINCRONIZARE ISTORIC ---
            // Când un client nou intră, îi trimitem tot istoricul
            synchronized(server.messageHistory) {
                for (oldMessage in server.messageHistory) {
                    try {
                        this.send(oldMessage)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }

        override fun onClose(code: WebSocketFrame.CloseCode?, reason: String?, initiatedByRemote: Boolean) {
            synchronized(server.webSocketSockets) { server.webSocketSockets.remove(this) }
            if (server.webSocketSockets.isEmpty()) {
                server.listener.onClientDisconnected()
            }
        }

        override fun onMessage(message: WebSocketFrame) {
            val text = message.textPayload

            // Trimitem la Activity (ca să plece și în Mesh)
            server.listener.onMessageFromWeb(text)

            // Trimitem la ceilalți clienți Web (și salvăm în istoric automat prin broadcastToAll)
            server.broadcastToAll(text)
        }

        override fun onPong(pong: WebSocketFrame?) {}
        override fun onException(exception: IOException?) {}
    }
}