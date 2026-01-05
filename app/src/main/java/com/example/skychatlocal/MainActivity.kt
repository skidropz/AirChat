package com.example.skychatlocal

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.format.Formatter
import android.view.WindowManager
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import com.google.zxing.common.BitMatrix
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections
import kotlin.math.roundToInt

class MainActivity : AppCompatActivity() {

    private var server: LocalServer? = null
    private val PORT = 8080

    override fun onCreate(savedInstanceState: Bundle?) {
        // 1. Inițializează Splash Screen (TREBUIE să fie prima linie)
        val splashScreen = installSplashScreen()

        // 2. FORȚEAZĂ TEMA corectă pentru a evita eroarea "IllegalStateException"
        setTheme(R.style.Theme_SkyChatLocal)

        super.onCreate(savedInstanceState)

        // 3. Logica de menținere a Splash-ului (2 secunde)
        var keepShowing = true
        splashScreen.setKeepOnScreenCondition { keepShowing }
        Handler(Looper.getMainLooper()).postDelayed({
            keepShowing = false
        }, 2000)

        setContentView(R.layout.activity_main)

        // Permisiuni audio
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                100
            )
        }

        val ipText = findViewById<TextView>(R.id.ipText)
        val qrImage = findViewById<ImageView>(R.id.qrImage)
        val webView = findViewById<WebView>(R.id.webView)

        // Pornire server
        try {
            server = LocalServer(this, PORT)
            server?.start(3600000)
        } catch (e: Exception) {
            Toast.makeText(this, "Eroare server: ${e.message}", Toast.LENGTH_LONG).show()
        }

        // IP inteligent
        val ipAddress = getSmartIpAddress()
        val url = "http://$ipAddress:$PORT"
        ipText.text = "$url"

        // Generare QR
        try {
            val smallSize = dpToPx(64)
            val largeSize = dpToPx(260)
            val smallQr = generateQrCode(url, smallSize)
            val largeQr = generateQrCode(url, largeSize)

            qrImage.setImageBitmap(smallQr)
            qrImage.setOnClickListener {
                showLargeQrDialog(largeQr)
            }
        } catch (e: Exception) {
            Toast.makeText(this, "Eroare generare QR: ${e.message}", Toast.LENGTH_SHORT).show()
        }

        setupWebView(webView)
    }

    private fun getSmartIpAddress(): String {
        try {
            val wifiManager =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val ipInt = wifiManager.connectionInfo.ipAddress
            if (ipInt != 0) return Formatter.formatIpAddress(ipInt)

            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                for (addr in Collections.list(intf.inetAddresses)) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        return addr.hostAddress ?: "192.168.43.1"
                    }
                }
            }
        } catch (_: Exception) { }
        return "192.168.43.1"
    }

    @Suppress("SetJavaScriptEnabled")
    private fun setupWebView(webView: WebView) {
        val settings = webView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.mediaPlaybackRequiresUserGesture = false
        settings.useWideViewPort = true
        settings.loadWithOverviewMode = true

        webView.webViewClient = WebViewClient()
        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                request.grant(request.resources)
            }
        }

        webView.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            }
        }

        webView.loadUrl("http://localhost:$PORT")
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density).roundToInt()

    private fun generateQrCode(text: String, size: Int): Bitmap {
        val bitMatrix: BitMatrix = MultiFormatWriter().encode(
            text, BarcodeFormat.QR_CODE, size, size, null
        )
        val width = bitMatrix.width
        val height = bitMatrix.height
        val pixels = IntArray(width * height)
        for (y in 0 until height) {
            val offset = y * width
            for (x in 0 until width) {
                pixels[offset + x] = if (bitMatrix.get(x, y)) Color.BLACK else Color.WHITE
            }
        }
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
            setPixels(pixels, 0, width, 0, 0, width, height)
        }
    }

    private fun showLargeQrDialog(bitmap: Bitmap) {
        val imageView = ImageView(this).apply {
            setImageBitmap(bitmap)
            adjustViewBounds = true
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.BLACK)
            setPadding(dpToPx(16), dpToPx(16), dpToPx(16), dpToPx(16))
        }
        AlertDialog.Builder(this).setView(imageView).setCancelable(true).show()
    }

    override fun onDestroy() {
        super.onDestroy()
        server?.stop()
    }
}