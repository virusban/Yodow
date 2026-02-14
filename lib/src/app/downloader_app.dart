import 'package:flutter/material.dart';

import '../ui/downloader_page.dart';

class DownloaderApp extends StatelessWidget {
  const DownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'yt-dlp Flutter Android',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const DownloaderPage(),
    );
  }
}
