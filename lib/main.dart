/// Mixtape for phones: your tapes and liked songs from the Mixtape Account, YouTube Music to search, play
/// and save for offline, Samples, lyrics and music videos, listening together, and music that keeps going
/// with the screen off, with a notification and (on Android) a home screen widget.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'app.dart';
import 'audio.dart';
import 'downloads.dart';
import 'history.dart';
import 'home_widgets.dart';
import 'library.dart';
import 'look.dart';
import 'phone.dart';
import 'scrobble.dart';
import 'settings.dart';
import 'store.dart';
import 'together.dart';
import 'ui/keys.dart';
import 'ui/now_playing.dart';
import 'ui/shell.dart';
import 'ui/turning.dart';
import 'video.dart';

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
  await PhoneInfo.the.load();
  if (PhoneInfo.the.lowRam) {
    // a phone with little memory keeps fewer covers decoded (one that's needed again is fetched again)
    PaintingBinding.instance.imageCache
      ..maximumSize = 300
      ..maximumSizeBytes = 48 << 20;
  }
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
      // the cover fills the whole music card on newer phones; one with little memory keeps it smaller
      artDownscaleWidth: PhoneInfo.the.lowRam ? 512 : 720,
      artDownscaleHeight: PhoneInfo.the.lowRam ? 512 : 720,
    ),
  );
  audio.autoplay = settings.autoplay;
  audio.setCrossfade(settings.crossfade, shape: settings.fadeShape, albums: settings.albumsWhole);
  audio.cardKeys = settings.cardKeys;
  // what changes in the settings reaches the player at once
  settings.addListener(() {
    audio.autoplay = settings.autoplay;
    audio.setCrossfade(settings.crossfade, shape: settings.fadeShape, albums: settings.albumsWhole);
    audio.cardKeys = settings.cardKeys;
    audio.refreshCard();
  });
  // the music card's heart and its "Not for me" (and the heart again when a song is liked in the app)
  audio.isLiked = library.isLiked;
  audio.toggleLike = library.toggleLike;
  audio.hideSong = (t) => library.hide(t, true);
  library.addListener(audio.refreshCard);
  final scrobbler = Scrobbler(settings, version: appVersion);
  audio.onPlayed = (t) {
    library.played(t);
    scrobbler.playingNow(t, pos: audio.player.position.inMilliseconds / 1000);
    // video mode: this song's video (and the next one's) is looked up as the song starts, so the player
    // has it at once, open or not
    if (settings.playerView == 'video') Videos.prepare([t, if (audio.upNext case final next?) next]).ignore();
  };
  audio.onHeard = (t, seconds, started) {
    history.heard(t, seconds, started);
    scrobbler.heard(t, seconds, started);
  };
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
  HomeWidgets.start();
  if (account.signedIn) library.sync();
}

class MixtapeApp extends StatefulWidget {
  const MixtapeApp({super.key});

  @override
  State<MixtapeApp> createState() => _MixtapeAppState();
}

class _MixtapeAppState extends State<MixtapeApp> with WidgetsBindingObserver {
  DateTime _away = DateTime.now();
  StreamSubscription<bool>? _cardTaps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appTurning();
    // a tap on the music card (lock screen, notification) opens the big player, like the other music apps
    _cardTaps = AudioService.notificationClicked.where((tapped) => tapped).listen((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = Shell.stateKey.currentContext;
        if (context != null && App.audio.current != null && !NowPlaying.showing) NowPlaying.open(context);
      });
    });
  }

  /// Phones stay upright, a tablet or an unfolded foldable turns with the hand (ui/turning.dart).
  @override
  void didChangeMetrics() => appTurning();

  @override
  void dispose() {
    _cardTaps?.cancel();
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
    // only the tape stock colors the whole app: other settings leave it be (a slider dragged in the
    // settings would otherwise redraw every page with each step)
    return ValueListenableBuilder<String>(
      valueListenable: App.settings.look,
      builder: (context, stock, _) => MaterialApp(
        title: 'Mixtape',
        debugShowCheckedModeBanner: false,
        theme: Look.theme(),
        builder: (context, child) => Keys(child: child ?? const SizedBox.shrink()),
        home: Shell(key: Shell.stateKey),
      ),
    );
  }
}
