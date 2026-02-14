enum MediaFormat {
  mp3,
  flac,
  wav,
  mp4,
  mkv;

  bool get isAudio => this == mp3 || this == flac || this == wav;

  String get label => name.toUpperCase();
}
