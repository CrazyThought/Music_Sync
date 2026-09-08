package com.example.music_sync_app

import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/**
 * MusicSync 主入口。
 *
 * 注册 MethodChannel「com.example.music_sync_app/audio_metadata」，
 * 供 Flutter 侧按文件路径调用系统 MediaMetadataRetriever
 * 提取音频元数据（标题/艺术家/专辑/时长/比特率）。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.example.music_sync_app/audio_metadata"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "extractAudioMeta") {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.success(emptyMap<String, String?>())
                        return@setMethodCallHandler
                    }
                    // MMR 为同步阻塞 API，须在子线程执行，避免阻塞 UI 线程导致 ANR
                    Thread {
                        val meta = extractAudioMeta(path)
                        Handler(Looper.getMainLooper()).post { result.success(meta) }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }
    }

    /** 使用 MediaMetadataRetriever 读取单个音频文件的元数据。 */
    private fun extractAudioMeta(path: String): Map<String, String?> {
        val file = File(path)
        if (!file.exists() || !file.isFile) return emptyMap()
        val retriever = MediaMetadataRetriever()
        try {
            FileInputStream(file).use { input ->
                // setDataSource(String path) 自 API 29 起弃用，这里用 FileDescriptor 读取
                retriever.setDataSource(input.fd)
            }
            val meta = mutableMapOf<String, String?>()
            meta["title"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
            meta["artist"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
            meta["album"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
            meta["duration_ms"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            meta["bitrate"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
            return meta
        } catch (_: Exception) {
            // 路径无效 / 格式不支持 / 解析失败等一律返回空结果，不向 Flutter 抛错
            return emptyMap()
        } finally {
            retriever.release()
        }
    }
}
