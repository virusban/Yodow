import 'package:flutter/material.dart';

import '../models/media_format.dart';
import '../services/downloader_bridge.dart';

class DownloaderPage extends StatefulWidget {
  const DownloaderPage({super.key});

  @override
  State<DownloaderPage> createState() => _DownloaderPageState();
}

class _DownloaderPageState extends State<DownloaderPage> {
  final TextEditingController _urlController = TextEditingController();
  final DownloaderBridge _bridge = DownloaderBridge();

  MediaFormat _format = MediaFormat.mp3;
  bool _isRunning = false;
  String _status = 'Ready';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    final String url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _status = 'Please paste a YouTube URL.';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _status = 'Processing...';
    });

    try {
      final DownloadResult result = await _bridge.download(url: url, format: _format);
      setState(() {
        _status = result.message;
      });
    } catch (error) {
      setState(() {
        _status = 'Error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube Downloader'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'YouTube URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MediaFormat>(
              initialValue: _format,
              decoration: const InputDecoration(
                labelText: 'Output format',
                border: OutlineInputBorder(),
              ),
              items: MediaFormat.values
                  .map(
                    (MediaFormat format) => DropdownMenuItem<MediaFormat>(
                      value: format,
                      child: Text(format.label),
                    ),
                  )
                  .toList(),
              onChanged: _isRunning
                  ? null
                  : (MediaFormat? value) {
                      if (value != null) {
                        setState(() {
                          _format = value;
                        });
                      }
                    },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isRunning ? null : _startDownload,
              child: Text(_isRunning ? 'Working...' : 'Download'),
            ),
            const SizedBox(height: 20),
            const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(child: Text(_status)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
