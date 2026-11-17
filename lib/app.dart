/// What every page works with: the music, the library, the account, the settings, the songs saved on
/// the phone, the listening history and Samples. They are made once when the app starts (see main.dart)
/// and live as long as the app.
library;

import 'account.dart';
import 'audio.dart';
import 'downloads.dart';
import 'history.dart';
import 'library.dart';
import 'samples.dart';
import 'settings.dart';
import 'together.dart';

/// This version of the phone app (pubspec.yaml's, for what the app says about itself).
const appVersion = '0.3.1';

class App {
  static late MixtapeAudio audio;
  static late Library library;
  static late Account account;
  static late Settings settings;
  static late History history;
  static late Together together;

  static Downloads get downloads => Downloads.the;

  static Samples? _samples;

  /// Samples, made the first time it opens.
  static Samples get samples => _samples ??= Samples(
        seeds: () => [...library.liked.reversed.take(80), ...library.recent.take(30)],
        known: () => {
          for (final t in library.liked) t.id,
          for (final t in library.recent) t.id,
          for (final p in history.plays) p.track.id,
        },
        unwanted: library.isHidden,
      );
}
