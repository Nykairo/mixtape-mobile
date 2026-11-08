# Mixtape for Android

Your tapes from Mixtape on the computer, in your pocket. Sign in with your Mixtape Account and your
tapes (with their shells, label papers and sticky notes) and your liked songs come over; whatever you
change on the phone goes back.
Search YouTube Music, play a song and songs like it keep coming. The music keeps going with the screen
off, with its keys in the notification, on the lock screen, on headphones and in a home screen widget.

## Install

**Android 7 or newer:** grab `Mixtape-<version>.apk` from the [releases](../../releases), open it on the
phone and allow the install. (A phone from before 2017 or so may need `Mixtape-<version>-older-phones.apk`.)

**iPhone:** the releases have `Mixtape-<version>.ipa`, built without a signature (there's no App Store
version). Sign it on its way onto the phone with your own Apple ID, using
[AltStore](https://altstore.io), [SideStore](https://sidestore.io) or [Sideloadly](https://sideloadly.io).
With a free Apple ID the signature lasts seven days, and AltStore or SideStore renew it by themselves.

## What's in it

- **Your tapes**, drawn like on the computer: shell, label paper, stripes, sticky note, handwriting,
  and reels that turn while a tape plays. Make tapes, rename them, put songs on them or take them off.
- **Liked songs**, in step with the computer in both directions.
- **Search** on YouTube Music. Playing a song plays songs like it after (Settings can switch that off).
- **Queue**: play next, add to queue, swipe a song away, shuffle, repeat.
- **Picks up where you left off**: the last song is loaded and waiting when the app opens.
- **Home screen widget** with the song, its cover on a little cassette, and back, play and next.

The stickers, photos and doodles from the computer's tape studio come over as the computer drew them
(Mixtape 3.8 or newer on the computer). Not yet: a home screen widget on the iPhone (the lock screen and
Control Center show the song and its keys).

## How it's built

Flutter for the screens, [just_audio](https://pub.dev/packages/just_audio) and
[audio_service](https://pub.dev/packages/audio_service) for playing in the background, and
[NewPipe Extractor](https://github.com/TeamNewPipe/NewPipeExtractor) on the Android side (in
`packages/mixtape_native`) for YouTube Music. On the iPhone, and on Android when NewPipe can't,
`lib/innertube.dart` asks YouTube Music directly, the way its own apps do. The Android widget is a
plain app widget, drawn in Kotlin.

YouTube addresses run out after a few hours, so a song's bytes come through a small reader in
`lib/audio.dart` that looks the address up again when YouTube stops taking it and carries on where a
dropped connection left off. It reads a few minutes ahead and then only a little faster than the music
plays, so long songs don't pile up in memory.

Every push to `main` is checked (`flutter analyze`, `flutter test`), built and released by
`.github/workflows/android.yml`.

## Building it yourself

```sh
flutter create --platforms=android --org dev.softwarevault --project-name mixtape .
flutter build apk --release
```

The first line only adds the files Flutter makes for every Android app (the Gradle wrapper); nothing
here is overwritten.

## License

GPL 3, see [LICENSE](LICENSE). NewPipe Extractor is GPL 3 as well. The fonts (Barlow and Covered By
Your Grace) come with their own OFL licenses in `assets/fonts`.
