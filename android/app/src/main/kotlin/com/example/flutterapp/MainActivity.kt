package com.example.flutterapp

import android.os.Build
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "yt_dlp_bridge"
    private val executor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "download" -> handleDownload(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleDownload(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        val format = call.argument<String>("format")?.trim()?.lowercase().orEmpty()

        if (url.isBlank()) {
            result.success(mapOf("success" to false, "message" to "URL is required"))
            return
        }

        if (format !in setOf("mp3", "flac", "wav", "mp4", "mkv")) {
            result.success(mapOf("success" to false, "message" to "Unsupported format: $format"))
            return
        }

        executor.execute {
            runCatching {
                val commandResult = runDownload(url, format)
                runOnUiThread { result.success(commandResult) }
            }.getOrElse { error ->
                runOnUiThread {
                    result.success(
                        mapOf(
                            "success" to false,
                            "message" to (error.message ?: "Unknown error"),
                        )
                    )
                }
            }
        }
    }

    private fun runDownload(url: String, format: String): Map<String, Any> {
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
        val ytDlp = ensureBinary("yt-dlp", abi)
        val ffmpeg = ensureBinary("ffmpeg", abi)

        val outputDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: File(filesDir, "downloads")
        outputDir.mkdirs()

        val outputTemplate = File(outputDir, "%(title)s.%(ext)s").absolutePath

        val command = mutableListOf(
            ytDlp.absolutePath,
            "--ffmpeg-location", ffmpeg.parentFile.absolutePath,
            "-o", outputTemplate,
            "--no-playlist",
            url,
        )

        if (format in setOf("mp3", "flac", "wav")) {
            command.addAll(
                listOf(
                    "--extract-audio",
                    "--audio-format", format,
                    "--embed-metadata",
                    "--embed-thumbnail",
                    "--add-metadata",
                )
            )
        } else {
            command.addAll(
                listOf(
                    "-f", "bv*+ba/b",
                    "--merge-output-format", format,
                )
            )
        }

        val process = ProcessBuilder(command)
            .redirectErrorStream(true)
            .start()

        val output = process.inputStream.bufferedReader().readText()
        val exitCode = process.waitFor()

        return if (exitCode == 0) {
            mapOf("success" to true, "message" to "Completed.\n$output")
        } else {
            mapOf("success" to false, "message" to "Failed with code $exitCode.\n$output")
        }
    }

    private fun ensureBinary(binaryName: String, abi: String): File {
        val fromAsset = "assets/bin/android/$abi/$binaryName"
        val targetDir = File(filesDir, "bin/$abi").apply { mkdirs() }
        val outFile = File(targetDir, binaryName)

        if (!outFile.exists()) {
            assets.open(fromAsset).use { input ->
                outFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            outFile.setExecutable(true)
        }

        return outFile
    }
}
