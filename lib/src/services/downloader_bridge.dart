import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
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
  }) async {
    final YoutubeExplode yt = YoutubeExplode();
    try {
      final Video video = await yt.videos.get(url);
      final StreamManifest manifest = await yt.videos.streamsClient.getManifest(video.id);
      final Directory outDir = await _resolveOutputDirectory();
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
    final AudioOnlyStreamInfo stream = manifest.audioOnly.withHighestBitrate();

    final String inputPath = '${outDir.path}/$baseName.source.${stream.container.name}';
    final File inputFile = File(inputPath);
    await _downloadStream(yt, stream, inputFile);

    final String outputPath = '${outDir.path}/$baseName.${format.name}';
    final String thumbPath = '${outDir.path}/$baseName.thumb.jpg';
    await _downloadThumbnail(video.thumbnails.highResUrl, File(thumbPath));

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

    if (await inputFile.exists()) {
      await inputFile.delete();
    }
    final File thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      await thumbFile.delete();
    }

    if (ReturnCode.isSuccess(returnCode)) {
      return DownloadResult(success: true, message: 'Done: $outputPath');
    }

    final logs = await session.getAllLogsAsString();
    return DownloadResult(success: false, message: 'FFmpeg failed.\n$logs');
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

    await _downloadStream(yt, selectedStream, File(tempPath));

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
    final streamData = yt.videos.streamsClient.get(stream);
    final IOSink sink = outFile.openWrite();
    await for (final List<int> data in streamData) {
      sink.add(data);
    }
    await sink.flush();
    await sink.close();
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

  Future<Directory> _resolveOutputDirectory() async {
    final Directory? external = await getExternalStorageDirectory();
    final Directory base = external ?? await getApplicationDocumentsDirectory();
    final Directory out = Directory('${base.path}/downloads');
    await out.create(recursive: true);
    return out;
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
