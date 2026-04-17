package com.example.skychatlocal

import android.content.Context
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoWSD
import java.io.IOException
import java.util.LinkedList

class LocalServer(
    private val context: Context,
    port: Int,
    private val localIp: String,
    private val roomKey: String,
    private val shortCode: String,
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
        val host = session.headers["host"] ?: ""

        // CAPTIVE PORTAL INTERCEPT
        val isLocalHost = host.contains(localIp) || host.contains("127.0.0.1") || host.contains("localhost")
        if (host.isNotEmpty() && !isLocalHost) {
            val res = newFixedLengthResponse(Response.Status.REDIRECT, NanoHTTPD.MIME_PLAINTEXT, "")
            res.addHeader("Location", "http://$localIp:${this.listeningPort}/$shortCode")
            return res
        }

        // URI specifice de verificare a conexiunii pentru iOS si Android
        if (uri.contains("generate_204") || uri.contains("hotspot-detect.html") || uri.contains("success.txt")) {
            val res = newFixedLengthResponse(Response.Status.REDIRECT, NanoHTTPD.MIME_PLAINTEXT, "")
            res.addHeader("Location", "http://$localIp:${this.listeningPort}/$shortCode")
            return res
        }

        // REDIRECTIONARE ROOT SAU SHORT URL CATRE INDEX + HASH
        if (uri == "/" || uri.equals("/$shortCode", ignoreCase = true) || uri.equals("/$shortCode/", ignoreCase = true)) {
            val res = newFixedLengthResponse(Response.Status.REDIRECT, NanoHTTPD.MIME_PLAINTEXT, "")
            res.addHeader("Location", "/index.html#$roomKey")
            return res
        }
        
        // INTERCEPTARE PENTRU DESCARCAREA APK-ULUI VIRAL
        if (uri == "/download-app") {
            try {
                val apkPath = context.applicationInfo.sourceDir
                val apkFile = java.io.File(apkPath)
                val fis = java.io.FileInputStream(apkFile)
                return newFixedLengthResponse(
                    Response.Status.OK, 
                    "application/vnd.android.package-archive", 
                    fis, 
                    apkFile.length()
                ).apply {
                    addHeader("Content-Disposition", "attachment; filename=\"AirChat.apk\"")
                }
            } catch (e: Exception) {
                return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, NanoHTTPD.MIME_PLAINTEXT, "Eroare la servirea APK-ului.")
            }
        }

        if (uri == "/") uri = "/index.html"
        val assetPath = uri.trimStart('/')

        return try {
            val mimeType = when {
                uri.endsWith(".css") -> "text/css"
                uri.endsWith(".js") -> "application/javascript"
                uri.endsWith(".html") -> "text/html"
                uri.endsWith(".json") -> "application/json"
                uri.endsWith(".png") -> "image/png"
                uri.endsWith(".jpg") || uri.endsWith(".jpeg") -> "image/jpeg"
                uri.endsWith(".svg") -> "image/svg+xml"
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
        // Nu salvăm ping-urile sau update-urile de locație / status de seen în istoricul de chat
        val isTransient = message.contains("\"type\":\"location_update\"") || 
                          message.contains("\"type\":\"seen\"") || 
                          message.contains("\"innerType\":\"location_update\"") ||
                          message.contains("\"innerType\":\"seen\"") ||
                          message == "ping"
                          
        // 1. Salvăm în istoric doar mesajele persistente
        if (!isTransient) {
            synchronized(messageHistory) {
                if (messageHistory.size >= MAX_HISTORY) {
                    messageHistory.removeFirst()
                }
                messageHistory.add(message)
            }
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