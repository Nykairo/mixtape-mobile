// The whole app in a box, for the tests that open its pages: a folder of its own, an account that lives
// in memory, YouTube Music answering from the files in test/fixtures, and an audio player that goes
// through the motions without a sound.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixtape/account.dart';
import 'package:mixtape/app.dart';
import 'package:mixtape/audio.dart';
import 'package:mixtape/downloads.dart';
import 'package:mixtape/history.dart';
import 'package:mixtape/innertube.dart';
import 'package:mixtape/library.dart';
import 'package:mixtape/look.dart';
import 'package:mixtape/lyrics.dart';
import 'package:mixtape/model.dart';
import 'package:mixtape/music.dart';
import 'package:mixtape/settings.dart';
import 'package:mixtape/store.dart';
import 'package:mixtape/together.dart';
import 'package:mixtape/ui/shell.dart';
import 'package:mixtape/youtube.dart';

/// Whether this run also takes pictures of the pages:
/// `flutter test --dart-define=PICTURES=true --update-goldens test/pages_test.dart`.
/// Covers come from the internet then, and every scene is saved to test/goldens.
const pictures = bool.fromEnvironment('PICTURES');

/// An account that keeps its tapes and library in memory instead of on the server.
class FakeAccount extends Account {
  FakeAccount() {
    session = Session(uid: 'u1', username: 'tester', display: 'Tester', access: 'a', refresh: 'r', expires: 9e12);
  }

  final rows = <String, Map<String, Object?>>{}; // name -> {data, deleted, updated_at}
  Map<String, Object?> library = {};
  int clock = 0;
  int pushes = 0;

  /// Invites to rooms that wait for this account, and the people who sent them (by id).
  List<Map<String, Object?>> waiting = [];
  Map<String, Map<String, Object?>> known = {};

  String _stamp() => '2026-11-08T12:00:${(clock++).toString().padLeft(2, '0')}Z';

  void serverPut(String name, Map<String, Object?> data, {bool deleted = false}) =>
      rows[name] = {'name': name, 'data': data, 'deleted': deleted, 'updated_at': _stamp()};

  @override
  Future<List<Map<String, Object?>>> pullTapes({String since = ''}) async {
    final out = [
      for (final r in rows.values)
        if (since.isEmpty || '${r['updated_at']}'.compareTo(since) > 0) Map<String, Object?>.from(r),
    ]..sort((a, b) => '${a['updated_at']}'.compareTo('${b['updated_at']}'));
    return out;
  }

  @override
  Future<void> pushTapes(Map<String, Map<String, Object?>> tapes) async {
    pushes++;
    tapes.forEach((name, data) => serverPut(name, data));
  }

  @override
  Future<void> dropTape(String name) async => serverPut(name, const {}, deleted: true);

  @override
  Future<Map<String, Object?>> pullLibrary() async =>
      library.isEmpty ? const {} : {'data': library, 'updated_at': _stamp()};

  @override
  Future<void> pushLibrary(Map<String, Object?> data) async => library = Map.of(data);

  @override
  Future<List<Map<String, Object?>>> invites() async => waiting;

  @override
  Future<void> dropInvite(String sender) async => waiting = [
        for (final i in waiting)
          if (i['sender'] != sender) i,
      ];

  @override
  Future<Map<String, Map<String, Object?>>> people(Iterable<String> ids) async => {
        for (final id in ids)
          if (known[id] case final Map<String, Object?> p) id: p,
      };

  @override
  Future<Map<String, List<int>>> pullPictures(Iterable<String> names) async => {};

  @override
  Future<void> publish(Map<String, Object?> state) async {}

  @override
  Future<void> unpublish(String device) async {}

  @override
  Future<double> serverTime() async => DateTime.now().millisecondsSinceEpoch / 1000;
}

Map<String, Object?> fixture(String name) =>
    Map<String, Object?>.from(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map);

/// YouTube Music, from the files: which answer goes with which question.
Future<http.Response> _youtube(http.Request request) async {
  final url = '${request.url}';
  Object? sent;
  try {
    sent = jsonDecode(request.body);
  } on FormatException {
    sent = null;
  }
  final body = sent is Map ? sent : const <String, Object?>{};
  final id = '${body['browseId'] ?? ''}';
  final context = body['context'];
  final client = context is Map ? context['client'] : null;
  final mobile = client is Map && client['clientName'] == 'ANDROID_MUSIC';
  String? name;
  if (url.contains('get_search_suggestions')) {
    name = 'suggestions';
  } else if (url.contains('/search')) {
    final filter = [
      for (final f in InnerTube.filters.entries)
        if (f.value == body['params']) f.key,
    ];
    name = switch (filter.isEmpty ? '' : filter.first) {
      'songs' => 'search_songs',
      'albums' => 'search_albums',
      'artists' => 'search_artists',
      'videos' => 'search_videos',
      _ => 'search_all',
    };
  } else if (url.contains('/next')) {
    name = url.contains('music.youtube.com') ? 'next' : 'web_next';
  } else if (url.contains('/browse')) {
    if (id == 'FEmusic_home') {
      name = 'home';
    } else if (id == 'FEmusic_moods_and_genres') {
      name = 'moods';
    } else if (id.startsWith('UC')) {
      name = 'artist';
    } else if (id.startsWith('MPRE')) {
      name = 'album';
    } else if (id.startsWith('MPLY')) {
      name = mobile ? 'lyrics_timed' : 'lyrics_plain';
    } else if (id.startsWith('MPTR')) {
      name = 'related';
    }
  }
  if (name == null) return http.Response('{}', 404);
  return http.Response.bytes(File('test/fixtures/$name.json').readAsBytesSync(), 200,
      headers: const {'content-type': 'application/json'});
}

/// The audio plugins and the app's own Android side aren't there in a test: every question to them
/// gets a yes with nothing in it, which is all the app needs to carry on. The player gets a little
/// more (see [_Deck]).
void quietPlugins() {
  const codec = StandardMethodCodec();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.allMessagesHandler = (channel, handler, message) async {
    if (channel.startsWith('com.ryanheise.just_audio')) return _Deck.answer(channel, message);
    if (channel.startsWith('com.ryanheise.') || channel == 'mixtape/native') return codec.encodeSuccessEnvelope(null);
    return handler?.call(message);
  };
}

/// just_audio's half on the phone, played by the tests: it says yes to everything, says a song is
/// ready as soon as it's loaded, and goes to the song a seek asks for. That's as far as the app's
/// player has to get to show what plays (just_audio waits for "ready" before a song counts as loaded).
class _Deck {
  static const _codec = StandardMethodCodec();
  static const _methods = 'com.ryanheise.just_audio.methods.';
  static final _at = <String, int>{}; // which song each player is on

  static ByteData answer(String channel, ByteData? message) {
    if (channel.startsWith(_methods) && message != null) {
      final id = channel.substring(_methods.length);
      final call = _codec.decodeMethodCall(message);
      final args = call.arguments is Map ? call.arguments as Map : const <Object?, Object?>{};
      if (call.method == 'load') {
        _at[id] = args['initialIndex'] is int ? args['initialIndex'] as int : 0;
        _ready(id, args['initialPosition']);
      } else if (call.method == 'seek') {
        if (args['index'] is int) _at[id] = args['index'] as int;
        _ready(id, args['position']);
      }
    }
    return _codec.encodeSuccessEnvelope(const <String, Object?>{});
  }

  static void _ready(String id, Object? position) {
    final at = position is int ? position : 0;
    final event = _codec.encodeSuccessEnvelope({
      'processingState': 3, // ready
      'updateTime': DateTime.now().millisecondsSinceEpoch,
      'updatePosition': at,
      'bufferedPosition': at,
      'duration': null,
      'currentIndex': _at[id],
    });
    // after the answer to the call, the way the phone sends it
    scheduleMicrotask(() => ui.channelBuffers.push('com.ryanheise.just_audio.events.$id', event, (_) {}));
  }
}

/// The app's fonts and the icon font, so pictures show letters and not boxes.
Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(rootBundle.load(f));
    }
    await loader.load();
  }

  await family('Barlow', [
    'assets/fonts/Barlow-Regular.ttf',
    'assets/fonts/Barlow-Medium.ttf',
    'assets/fonts/Barlow-SemiBold.ttf',
    'assets/fonts/Barlow-Bold.ttf',
  ]);
  await family('Barlow Condensed', [
    'assets/fonts/BarlowCondensed-Medium.ttf',
    'assets/fonts/BarlowCondensed-SemiBold.ttf',
    'assets/fonts/BarlowCondensed-Bold.ttf',
  ]);
  await family('Covered By Your Grace', ['assets/fonts/CoveredByYourGrace.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

class Box {
  static late FakeAccount account;

  /// Real songs (from a search for Daft Punk), for tapes, likes and the queue.
  static late List<Track> songs;

  static bool _open = false;

  /// Sets the app up once: call it from setUpAll.
  static Future<void> open() async {
    if (_open) return;
    _open = true;
    TestWidgetsFlutterBinding.ensureInitialized();
    quietPlugins();
    if (pictures) HttpOverrides.global = null; // the real internet, for the covers
    final dir = Directory.systemTemp.createTempSync('mixtape-box');
    await Store.open(at: dir);
    YouTube.inner = InnerTube(client: MockClient(_youtube));
    LyricsFinder.the = LyricsFinder(client: MockClient((_) async => http.Response('', 404)));
    songs = [for (final i in parseSearch(fixture('search_songs')).items) i.track];

    final settings = Settings();
    await settings.load();
    account = FakeAccount();
    final mine = account.session;
    account.session = null; // signed out while the shelves fill, so nothing tries to sync meanwhile
    final library = Library(account);
    await library.load();
    library.setNote(library.newTape('Road trip', songs: songs.take(8).toList()), 'windows down');
    library.setDesign(
      library.newTape('Night drive', songs: songs.skip(4).take(6).toList()),
      {'shell': 'clear', 'finish': 'glitter', 'tape': 'chrome', 'pen': 'marker'},
      paper: 7,
    );
    library.setDesign(
      library.newTape('Gym', songs: songs.skip(9).take(5).toList()),
      {'shell': 'red', 'hub': 'black', 'stripes': 'band', 'pen': 'type'},
      paper: 4,
    );
    library.newTape('Sunday morning', songs: songs.skip(2).take(4).toList());
    library.newTape('Podcast: Late Show', songs: songs.skip(12).take(2).toList());
    library.pin('Road trip', true);
    for (final t in songs.skip(1).take(7)) {
      library.toggleLike(t);
    }
    for (final t in songs.take(6).toList().reversed) {
      library.played(t);
    }
    for (final q in ['daft punk', 'get lucky', 'bon iver']) {
      library.searched(q);
    }
    await library.flush();
    account.session = mine;

    final history = History();
    await history.load();
    final now = DateTime.now();
    for (var day = 0; day < 24; day++) {
      for (var k = 0; k < 5; k++) {
        final t = songs[(day * 3 + k * k) % songs.length];
        history.heard(t, 150 + (day * 37 + k * 11) % 90, now.subtract(Duration(days: day, hours: (k * 5 + day) % 20)));
      }
    }
    await history.flush();

    // five songs "on the phone": a file each and their lines in the list
    final offline = Directory('${dir.path}/offline')..createSync();
    final saved = <String, Object?>{};
    for (final t in songs.take(5)) {
      File('${offline.path}/${t.id}.m4a').writeAsBytesSync(List.filled(2048, 0));
      saved[t.id] = {'track': t.toJson(), 'file': '${t.id}.m4a', 'bytes': 3200000 + t.dur * 9000};
    }
    await Store.the.write('offline.json', {'songs': saved, 'waiting': const <Object?>[]});
    await Downloads.the.load();

    final audio = MixtapeAudio();
    await audio.ready;
    audio.unwanted = library.isHidden;
    App.audio = audio;
    App.library = library;
    App.account = account;
    App.settings = settings;
    App.history = history;
    App.together = Together(account, audio, sharing: () => false);
  }

  /// Puts a queue into the player the way a tap on a tape does. Nothing sounds, but the app has a
  /// song that plays, a queue, and a little player to show.
  static Future<void> startMusic(WidgetTester tester, {int at = 0}) async {
    await tester.runAsync(() async {
      await App.audio
          .playSongs(songs.take(8).toList(), start: at, from: 'Road trip', tape: 'Road trip')
          .timeout(const Duration(seconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
  }
}

/// The app as it starts, on a phone-sized screen. [bars] is the room the status bar takes at the top
/// and the keys or the gesture bar at the bottom; [builder] goes around everything (devices_test draws
/// those bars with it).
Future<void> pumpApp(WidgetTester tester,
    {Size size = const Size(412, 892), EdgeInsets bars = EdgeInsets.zero, TransitionBuilder? builder}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  final pad = FakeViewPadding(left: bars.left * 2, top: bars.top * 2, right: bars.right * 2, bottom: bars.bottom * 2);
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
  addTearDown(tester.view.reset);
  Shell.tab.value = 0;
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: Look.theme(),
    builder: builder,
    home: Shell(key: Shell.stateKey),
  ));
  await wait(tester);
}

/// Lets a page finish what it started: its questions get their answers, its covers come in (in a run
/// that takes pictures), its animations move on. Not pumpAndSettle: the reels never stop turning.
///
/// Every round lets a little real time pass too. The players were set up outside the test's clock,
/// and whatever waits on them only moves on while the real one runs.
Future<void> wait(WidgetTester tester, {int rounds = 4}) async {
  for (var k = 0; k < rounds; k++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: pictures ? 450 : 40)));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Saves what the screen shows to test/goldens/[name].png, in a run that takes pictures.
Future<void> shot(WidgetTester tester, String name) async {
  if (!pictures) return;
  await wait(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

/// Takes the app off the screen again and lets its timers run out, so the next test starts clean.
Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // long enough for the delayed saves, and for the covers' connections to time out (15 seconds)
  await tester.pump(const Duration(seconds: 20));
  await tester.pump(const Duration(seconds: 20));
}
