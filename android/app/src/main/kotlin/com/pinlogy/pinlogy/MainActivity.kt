package com.pinlogy.pinlogy

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import java.io.File
import java.util.UUID
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * SNSなどからの共有 Intent を受け取り、Flutter の MethodChannel へ渡す。
 * 解析は Flutter 側で後続処理するため、ここでは保存用ペイロードの整形のみ行う。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.pinlogy/share"
    private var methodChannel: MethodChannel? = null
    private var pendingShare: HashMap<String, Any?>? = null
    private var flutterReady = false
    private var dartReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedMedia" -> {
                    dartReady = true
                    result.success(pendingShare)
                    pendingShare = null
                }
                else -> result.notImplemented()
            }
        }
        flutterReady = true
        handleShareIntent(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cleanupSharedCache()
        // configureFlutterEngine より先に来る場合に備えて保持
        if (!flutterReady) {
            pendingShare = extractShare(intent) ?: pendingShare
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?) {
        val payload = extractShare(intent) ?: return
        if (dartReady && methodChannel != null) {
            methodChannel?.invokeMethod("onShared", payload)
        } else {
            pendingShare = payload
        }
    }

    private fun extractShare(intent: Intent?): HashMap<String, Any?>? {
        if (intent == null) return null
        val action = intent.action ?: return null
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }

        val payload = HashMap<String, Any?>()
        val type = intent.type ?: ""
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)

        if (!text.isNullOrBlank()) {
            val trimmed = text.trim()
            if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
                val first = trimmed.split(Regex("\\s+")).first()
                payload["url"] = first
                if (trimmed != first) {
                    payload["text"] = trimmed
                }
            } else {
                payload["text"] = trimmed
            }
        }
        if (!subject.isNullOrBlank()) {
            payload["title"] = subject
        }

        val paths = ArrayList<String>()
        if (action == Intent.ACTION_SEND) {
            val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (stream != null) {
                // 一時的な読み取り権限を保持
                try {
                    grantUriPermission(
                        packageName,
                        stream,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: Exception) {
                }
                copySharedUri(stream, type)?.let(paths::add)
            }
        } else if (action == Intent.ACTION_SEND_MULTIPLE) {
            val streams = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            streams?.forEach { uri ->
                try {
                    grantUriPermission(
                        packageName,
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: Exception) {
                }
                copySharedUri(uri, type)?.let(paths::add)
            }
        }
        if (paths.isNotEmpty()) {
            payload["imagePaths"] = paths
        }

        payload["service"] = guessService(
            (payload["url"] as? String) ?: text,
            type,
        )

        if (payload["title"] == null) {
            when {
                payload["url"] != null -> payload["title"] = "共有されたURL"
                paths.isNotEmpty() && type.startsWith("image") ->
                    payload["title"] = "共有された画像"
                paths.isNotEmpty() && type.startsWith("video") ->
                    payload["title"] = "共有された動画"
                payload["text"] != null -> payload["title"] = "共有されたテキスト"
                else -> payload["title"] = "共有された投稿"
            }
        }

        // 中身が完全に空なら無視
        if (payload["url"] == null &&
            payload["text"] == null &&
            paths.isEmpty()
        ) {
            return null
        }
        return payload
    }

    private fun guessService(raw: String?, mime: String): String {
        val hay = (raw ?: "").lowercase()
        return when {
            hay.contains("instagram.com") -> "Instagram"
            hay.contains("tiktok.com") -> "TikTok"
            hay.contains("youtube.com") || hay.contains("youtu.be") -> "YouTube"
            mime.startsWith("image") -> "画像"
            mime.startsWith("video") -> "動画"
            hay.startsWith("http") -> "URL"
            else -> "その他"
        }
    }

    private fun copySharedUri(uri: Uri, mime: String): String? {
        return try {
            val extension = when {
                mime.contains("png") -> "png"
                mime.contains("webp") -> "webp"
                mime.startsWith("video") -> "mp4"
                else -> "jpg"
            }
            val directory = File(cacheDir, "shared_media").apply { mkdirs() }
            val output = File(directory, "${UUID.randomUUID()}.$extension")
            contentResolver.openInputStream(uri)?.use { input ->
                output.outputStream().use { stream -> input.copyTo(stream) }
            } ?: return null
            output.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun cleanupSharedCache() {
        val cutoff = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        File(cacheDir, "shared_media").listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) file.delete()
        }
    }
}
