import 'package:flutter/services.dart';

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
  static const MethodChannel _channel = MethodChannel('yt_dlp_bridge');

  Future<DownloadResult> download({
    required String url,
    required MediaFormat format,
  }) async {
    final dynamic result = await _channel.invokeMethod<dynamic>('download', <String, dynamic>{
      'url': url,
      'format': format.name,
    });

    if (result is Map) {
      return DownloadResult(
        success: result['success'] == true,
        message: (result['message'] ?? 'No message returned').toString(),
      );
    }

    return const DownloadResult(success: false, message: 'Unexpected platform response');
  }
}
