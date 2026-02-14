import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/media_format.dart';

class DownloadResult {
  const DownloadResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class DownloaderBridge {
  Future<DownloadResult> download({
    required String url,
    required MediaFormat format,
    required String outputDirectoryPath,
  }) async {
    final YoutubeExplode yt = YoutubeExplode();
    try {
      final Video video = await yt.videos.get(url);
      final StreamManifest manifest = await _getRobustManifest(yt, video.id);
      final Directory outDir = Directory(outputDirectoryPath);
      await outDir.create(recursive: true);
      await _assertWritableDirectory(outDir);
      final String baseName = _safeName(video.title);

      if (format.isAudio) {
        return _downloadAudio(
          yt: yt,
          video: video,
          manifest: manifest,
          outDir: outDir,
          baseName: baseName,
          format: format,
        );
      }

      return _downloadVideo(
        yt: yt,
        manifest: manifest,
        outDir: outDir,
        baseName: baseName,
        format: format,
      );
    } catch (error) {
      return DownloadResult(success: false, message: 'Error: $error');
    } finally {
      yt.close();
    }
  }

  Future<DownloadResult> _downloadAudio({
    required YoutubeExplode yt,
    required Video video,
    required StreamManifest manifest,
    required Directory outDir,
    required String baseName,
    required MediaFormat format,
  }) async {
    final List<AudioOnlyStreamInfo> candidates = manifest.audioOnly.toList()
      ..sort(
        (AudioOnlyStreamInfo a, AudioOnlyStreamInfo b) =>
            b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
      );
    if (candidates.isEmpty) {
      return const DownloadResult(success: false, message: 'No audio stream found.');
    }

    final String outputPath = '${outDir.path}/$baseName.${format.name}';
    final String thumbPath = '${outDir.path}/$baseName.thumb.jpg';
    await _downloadThumbnail(video.thumbnails.highResUrl, File(thumbPath));

    String lastError = 'Unknown error';
    for (final AudioOnlyStreamInfo stream in candidates.take(3)) {
      final String inputPath = '${outDir.path}/$baseName.source.${stream.container.name}';
      final File inputFile = File(inputPath);
      try {
        await _downloadStreamWithRetry(yt, stream, inputFile);

        final List<String> ffmpegArgs = _audioArguments(
          inputPath: inputPath,
          outputPath: outputPath,
          thumbPath: thumbPath,
          format: format,
          title: video.title,
          artist: video.author,
        );

        final session = await FFmpegKit.executeWithArguments(ffmpegArgs);
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          return DownloadResult(success: true, message: 'Done: $outputPath');
        }

        lastError = await session.getAllLogsAsString() ?? 'No ffmpeg logs available.';
      } catch (error) {
        lastError = error.toString();
      } finally {
        if (await inputFile.exists()) {
          await inputFile.delete();
        }
      }
    }

    final File thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      await thumbFile.delete();
    }

    return DownloadResult(
      success: false,
      message: 'FFmpeg failed after stream retries.\n$lastError',
    );
  }

  Future<DownloadResult> _downloadVideo({
    required YoutubeExplode yt,
    required StreamManifest manifest,
    required Directory outDir,
    required String baseName,
    required MediaFormat format,
  }) async {
    MuxedStreamInfo? stream = manifest.muxed
        .where((MuxedStreamInfo s) => s.container.name == format.name)
        .sortByBitrate()
        .lastOrNull;

    stream ??= manifest.muxed.withHighestBitrate();
    final MuxedStreamInfo selectedStream = stream;

    final String tempPath = '${outDir.path}/$baseName.source.${selectedStream.container.name}';
    final String outputPath = '${outDir.path}/$baseName.${format.name}';

    await _downloadStreamWithRetry(yt, selectedStream, File(tempPath));

    if (selectedStream.container.name == format.name) {
      await File(tempPath).rename(outputPath);
      return DownloadResult(success: true, message: 'Done: $outputPath');
    }

    final session = await FFmpegKit.executeWithArguments(<String>[
      '-y',
      '-i',
      tempPath,
      '-c',
      'copy',
      outputPath,
    ]);
    final returnCode = await session.getReturnCode();
    final File tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    if (ReturnCode.isSuccess(returnCode)) {
      return DownloadResult(success: true, message: 'Done: $outputPath');
    }

    final logs = await session.getAllLogsAsString();
    return DownloadResult(success: false, message: 'FFmpeg failed.\n$logs');
  }

  Future<void> _downloadStream(
    YoutubeExplode yt,
    StreamInfo stream,
    File outFile,
  ) async {
    final int expectedBytes = stream.size.totalBytes;
    int writtenBytes = await _downloadWithExplodeStream(yt, stream, outFile);

    if (writtenBytes <= 0 || writtenBytes < expectedBytes) {
      if (await outFile.exists()) {
        await outFile.delete();
      }
      writtenBytes = await _downloadWithDirectHttp(stream.url, outFile);
    }

    if (writtenBytes <= 0 || writtenBytes < expectedBytes) {
      throw Exception(
        'Incomplete download for ${outFile.path}. Expected $expectedBytes bytes, got $writtenBytes bytes.',
      );
    }
  }

  Future<int> _downloadWithExplodeStream(
    YoutubeExplode yt,
    StreamInfo stream,
    File outFile,
  ) async {
    final streamData = yt.videos.streamsClient.get(stream);
    final IOSink sink = outFile.openWrite();
    int writtenBytes = 0;
    await for (final List<int> data in streamData) {
      sink.add(data);
      writtenBytes += data.length;
    }
    await sink.flush();
    await sink.close();
    return writtenBytes;
  }

  Future<int> _downloadWithDirectHttp(Uri url, File outFile) async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    request.headers.set(HttpHeaders.refererHeader, 'https://www.youtube.com/');
    request.headers.set('origin', 'https://www.youtube.com');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    final HttpClientResponse response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      client.close(force: true);
      throw Exception('Direct stream request failed: HTTP ${response.statusCode}');
    }
    final IOSink sink = outFile.openWrite();
    int writtenBytes = 0;
    await for (final List<int> data in response) {
      sink.add(data);
      writtenBytes += data.length;
    }
    await sink.flush();
    await sink.close();
    client.close(force: true);
    return writtenBytes;
  }

  Future<void> _downloadStreamWithRetry(
    YoutubeExplode yt,
    StreamInfo stream,
    File outFile,
  ) async {
    const int maxAttempts = 3;
    Object? lastError;
    StreamInfo currentStream = stream;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (await outFile.exists()) {
          await outFile.delete();
        }
        await _downloadStream(yt, currentStream, outFile);
        return;
      } catch (error) {
        lastError = error;
        final String message = error.toString();
        if (message.contains('403') || message.contains('Incomplete download')) {
          final StreamManifest freshManifest =
              await _getRobustManifest(yt, currentStream.videoId);
          final StreamInfo? refreshed =
              _findStreamByTag(freshManifest.streams, currentStream.tag);
          if (refreshed != null) {
            currentStream = refreshed;
          }
        }
      }
    }
    throw Exception('Download failed after $maxAttempts attempts: $lastError');
  }

  Future<StreamManifest> _getRobustManifest(
    YoutubeExplode yt,
    VideoId videoId,
  ) {
    return yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: <YoutubeApiClient>[
        YoutubeApiClient.ios,
        YoutubeApiClient.android,
        YoutubeApiClient.tv,
      ],
    );
  }

  StreamInfo? _findStreamByTag(Iterable<StreamInfo> streams, int tag) {
    for (final StreamInfo stream in streams) {
      if (stream.tag == tag) {
        return stream;
      }
    }
    return null;
  }

  Future<void> _downloadThumbnail(String url, File outFile) async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    final HttpClientResponse response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Thumbnail request failed: HTTP ${response.statusCode}');
    }
    final IOSink sink = outFile.openWrite();
    await response.forEach(sink.add);
    await sink.flush();
    await sink.close();
    client.close(force: true);
  }

  Future<void> _assertWritableDirectory(Directory directory) async {
    final File probe = File('${directory.path}/.write_test_${DateTime.now().millisecondsSinceEpoch}');
    try {
      await probe.writeAsString('ok');
    } on FileSystemException catch (error) {
      throw Exception(
        'Cannot write to selected folder: ${directory.path}. '
        'Please pick another folder or grant storage access. Details: ${error.osError?.message ?? error.message}',
      );
    } finally {
      if (await probe.exists()) {
        await probe.delete();
      }
    }
  }

  List<String> _audioArguments({
    required String inputPath,
    required String outputPath,
    required String thumbPath,
    required MediaFormat format,
    required String title,
    required String artist,
  }) {
    if (format == MediaFormat.wav) {
      return <String>[
        '-y',
        '-i',
        inputPath,
        '-vn',
        '-metadata',
        'title=$title',
        '-metadata',
        'artist=$artist',
        outputPath,
      ];
    }

    final String codec = format == MediaFormat.flac ? 'flac' : 'libmp3lame';
    return <String>[
      '-y',
      '-i',
      inputPath,
      '-i',
      thumbPath,
      '-map',
      '0:a',
      '-map',
      '1:v',
      '-c:a',
      codec,
      '-c:v',
      'mjpeg',
      '-disposition:v',
      'attached_pic',
      '-metadata',
      'title=$title',
      '-metadata',
      'artist=$artist',
      '-metadata',
      'album=YouTube',
      outputPath,
    ];
  }

  String _safeName(String input) {
    final String cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'youtube_download' : cleaned;
  }
}

extension _MuxedSorting on Iterable<MuxedStreamInfo> {
  List<MuxedStreamInfo> sortByBitrate() {
    final List<MuxedStreamInfo> list = toList()
      ..sort(
        (MuxedStreamInfo a, MuxedStreamInfo b) =>
            a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond),
      );
    return list;
  }
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
