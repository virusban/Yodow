# yt-dlp Flutter Android

An Android (11+) Flutter application that downloads audio or video from YouTube using `yt-dlp` and converts/merges media with `ffmpeg`, fully on-device with bundled binaries.

This project is for educational and personal use only.

## Features

- Audio output: `mp3`, `flac`, `wav`
- Video output: `mp4`, `mkv`
- Metadata embedding for audio (`--embed-metadata`, `--embed-thumbnail`)
- Single-screen Flutter UI
- No backend required
- Android 11+ target

## Architecture

- Flutter UI sends `url` + `format` over `MethodChannel` (`yt_dlp_bridge`)
- Android `MainActivity` copies ABI-specific binaries from assets to app files dir
- Android executes `yt-dlp` and passes `--ffmpeg-location`
- Process output is returned to Flutter and shown in the status panel

## Project Layout

- `lib/`: Flutter app UI and channel bridge
- `android/`: Android host app and native command execution
- `assets/bin/android/<abi>/`: bundled binaries per ABI

## Binary Setup (Required)

Add real executable files before building:

- `assets/bin/android/arm64-v8a/yt-dlp`
- `assets/bin/android/arm64-v8a/ffmpeg`
- `assets/bin/android/armeabi-v7a/yt-dlp`
- `assets/bin/android/armeabi-v7a/ffmpeg`
- `assets/bin/android/x86_64/yt-dlp`
- `assets/bin/android/x86_64/ffmpeg`

## Build

```bash
flutter pub get
flutter build apk --release
```

APK output:

`build/app/outputs/flutter-apk/app-release.apk`

## Notes

- Current machine does not have Flutter in PATH, so build/test was not run in this session.
- Add legal disclaimers and ensure compliance with local law and YouTube Terms before distribution.
