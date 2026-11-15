/// Mixtape for phones: your tapes and liked songs from the Mixtape Account, YouTube Music to search, play
/// and save for offline, Samples, lyrics and music videos, listening together, and music that keeps going
/// with the screen off, with a notification and (on Android) a home screen widget.
library;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'app.dart';
import 'audio.dart';
import 'downloads.dart';
import 'history.dart';
import 'library.dart';
import 'look.dart';
import 'settings.dart';
import 'store.dart';
import 'together.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.open();
  final settings = Settings();
  await settings.load();
  final account = Account();
  await account.load();
  final library = Library(account);
  await library.load();
  final history = History();
  await history.load();
  await Downloads.the.load(); // before the music: saved songs play from their files
  final audio = await AudioService.init(
    builder: MixtapeAudio.new,
    config: AudioServiceConfig(
      androidNotificationChannelId: 'dev.softwarevault.mixtape.music',
      androidNotificationChannelName: 'Music',
      androidNotificationChannelDescription: 'What Mixtape plays, with its keys',
      androidNotificationIcon: 'drawable/ic_stat_mixtape',
      notificationColor: Look.accent,
      androidStopForegroundOnPause: true,
      preloadArtwork: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    ),
  );
  audio.autoplay = settings.autoplay;
  audio.onPlayed = library.played;
  audio.onHeard = history.heard;
  audio.unwanted = library.isHidden;
  App.audio = audio;
  App.library = library;
  App.account = account;
  App.settings = settings;
  App.history = history;
  App.together = Together(account, audio, sharing: () => settings.shareListening)..startSharing();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MixtapeApp());
  if (account.signedIn) library.sync();
}

class MixtapeApp extends StatefulWidget {
  const MixtapeApp({super.key});

  @override
  State<MixtapeApp> createState() => _MixtapeAppState();
}

class _MixtapeAppState extends State<MixtapeApp> with WidgetsBindingObserver {
  DateTime _away = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _away = DateTime.now();
      App.library.flush();
      App.settings.flush();
      App.history.flush();
      App.downloads.flush();
      App.audio.saveNow();
    } else if (state == AppLifecycleState.resumed) {
      // back after a while: what changed on the computer meanwhile comes in
      if (DateTime.now().difference(_away) > const Duration(seconds: 30) && App.account.signedIn) {
        App.library.sync();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.settings,
      builder: (context, _) => MaterialApp(
        title: 'Mixtape',
        debugShowCheckedModeBanner: false,
        theme: Look.theme(),
        home: Shell(key: Shell.key),
      ),
    );
  }
}
