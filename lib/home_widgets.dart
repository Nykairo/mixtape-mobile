/// Mixtape's home screen widgets, from the app's side: tells them what plays and which tapes there are,
/// and does what's tapped on them (like, shuffle, open a tape and play it). The widgets themselves are
/// drawn on the Android side (packages/mixtape_native: Widgets.kt) and by WidgetKit on the iPhone
/// (ios-extras/widgets).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:mixtape_native/mixtape_native.dart';

import 'app.dart';
import 'cassette.dart';
import 'look.dart';
import 'model.dart';
import 'store.dart';
import 'ui/shell.dart';
import 'ui/tape_page.dart';

class HomeWidgets {
  HomeWidgets._();

  static final _client = http.Client();
  static Timer? _soon;
  static Timer? _shelfSoon;
  static String _coverFor = '';
  static String _lastShelf = '';
  static bool _started = false;

  /// Starts telling the widgets about the music and the tapes, and listening to what's tapped on them.
  static void start() {
    if (_started || !(Platform.isAndroid || Platform.isIOS)) return;
    _started = true;
    final audio = App.audio;
    audio.mediaItem.listen((_) => _later());
    var was = audio.playbackState.value;
    audio.playbackState.listen((s) {
      // what the widgets show changes when the music starts or stops, shuffle flips, or someone jumps in
      // the song; the steady ticking of the time they work out by themselves
      final expected =
          was.playing ? was.updatePosition + s.updateTime.difference(was.updateTime) * was.speed : was.updatePosition;
      final jumped = (s.updatePosition - expected).abs() > const Duration(seconds: 2);
      if (s.playing != was.playing || s.shuffleMode != was.shuffleMode || jumped) _later();
      was = s;
    });
    App.library.addListener(() {
      _later();
      _shelfLater();
    });
    MixtapeNative.widgetTaps.listen(_tapped);
    _shelfLater();
    _later();
    _waiting();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final tape = await MixtapeNative.widgetLaunch();
      if (tape != null) _tapped(tape);
    });
  }

  static void _later() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 250), _send);
  }

  static void _shelfLater() {
    _shelfSoon?.cancel();
    _shelfSoon = Timer(const Duration(milliseconds: 800), _sendShelf);
  }

  /// The colors of a tape's cassette, as numbers for the widgets.
  static Map<String, Object?> colors(TapeLook l) => {
        'shell': l.shell.toARGB32(),
        'shellAlpha': l.shellAlpha,
        'paper': l.paper.toARGB32(),
        'ink': l.ink.toARGB32(),
        'stripes': [for (final c in l.stripes) c.toARGB32()],
        'stripeStyle': l.stripeStyle,
        'hub': (l.hub ?? const Color(0xFFE9E0CF)).toARGB32(),
        'tape': l.tape.toARGB32(),
        'screw': l.screw.toARGB32(),
        'screws': !l.noScrews,
      };

  static TapeLook _lookOf(Tape t) => TapeLook(slot: t.paper ?? slotFor(t.name), design: t.design);

  static Future<void> _send() async {
    final audio = App.audio;
    final t = audio.current;
    if (t == null) return;
    final art = await _cover(t);
    if (audio.current?.id != t.id) return; // another song meanwhile; its own turn draws it
    final view = audio.view;
    final player = audio.player;
    final tape = App.library.tapes[audio.fromTape];
    await MixtapeNative.widget({
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'playing': player.playing,
      'art': art,
      'liked': App.library.isLiked(t),
      'shuffle': player.shuffleModeEnabled,
      'position': player.position.inMilliseconds,
      'duration': (player.duration ?? Duration(seconds: t.dur)).inMilliseconds,
      'index': view.index,
      'count': view.songs.length,
      'tape': audio.fromTape,
      'colors': tape == null ? null : colors(_lookOf(tape)),
      'track': t.toJson(),
    });
  }

  /// The cover as a file the widgets' side can read, fetched once per song (big enough for the Cover
  /// widget on a big phone).
  static Future<String> _cover(Track t) async {
    final address = t.artAt(544);
    if (address.isEmpty) return '';
    final file = Store.the.file('widget_cover.jpg');
    if (_coverFor != t.id) {
      try {
        final res = await _client.get(Uri.parse(address)).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200 || res.bodyBytes.length > 2000000) return '';
        await file.writeAsBytes(res.bodyBytes, flush: true);
        _coverFor = t.id;
      } on Object {
        _coverFor = '';
        return '';
      }
    }
    return file.path;
  }

  /// The tapes for "My tapes": the pinned ones first, the liked songs, then the newest; eight at most.
  static Future<void> _sendShelf() async {
    final lib = App.library;
    final shelf = <Map<String, Object?>>[];
    final seen = <String>{};
    void add(String id) {
      if (shelf.length >= 8 || !seen.add(id)) return;
      if (id.isEmpty) {
        if (lib.liked.isEmpty) return;
        shelf.add({
          'id': '',
          'name': 'Liked songs',
          'songs': lib.liked.length,
          'colors': colors(TapeLook(slot: 3)),
          'liked': true,
        });
        return;
      }
      final t = lib.tapes[id];
      if (t == null || t.group == 'Local') return;
      shelf.add({'id': t.name, 'name': t.shownName, 'songs': t.songs.length, 'colors': colors(_lookOf(t)), 'liked': false});
    }

    for (final p in lib.pinned) {
      add(p);
    }
    add('');
    for (final t in lib.shownTapes.reversed) {
      add(t.name);
    }
    final said = jsonEncode(shelf);
    if (said == _lastShelf) return;
    _lastShelf = said;
    await MixtapeNative.shelf(shelf);
  }

  /// Likes tapped on a widget while the app was closed.
  static Future<void> _waiting() async {
    final raw = await MixtapeNative.widgetWaiting();
    try {
      for (final x in jsonDecode(raw) as List) {
        if (x is! Map) continue;
        final t = Track.fromJson(x['track']);
        if (t == null) continue;
        if (App.library.isLiked(t) != (x['liked'] == true)) App.library.toggleLike(t);
      }
    } on Object {
      // nothing usable waited
    }
  }

  static void _tapped(String what) {
    final audio = App.audio;
    // the keys on the iPhone's widgets come this way (on Android they go to the player directly)
    switch (what) {
      case 'play':
        audio.play();
      case 'pause':
        audio.pause();
      case 'next':
        audio.skipToNext();
      case 'previous':
        audio.skipToPrevious();
    }
    if (what == 'like') {
      final t = audio.current;
      if (t != null) App.library.toggleLike(t);
    } else if (what == 'shuffle') {
      audio.setShuffleMode(
          audio.player.shuffleModeEnabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);
    } else if (what.startsWith('tape:')) {
      _openTape(what.substring(5));
    }
    _later();
  }

  /// A tape tapped on "My tapes": its page opens and it plays from the top.
  static void _openTape(String id) {
    final lib = App.library;
    if (id.isEmpty) {
      final songs = lib.liked.reversed.toList();
      Shell.push(const TapePage.liked());
      if (songs.isNotEmpty) App.audio.playSongs(songs, from: 'Liked songs');
      return;
    }
    final tape = lib.tapes[id];
    if (tape == null) return;
    Shell.push(TapePage(tape: tape));
    if (tape.songs.isNotEmpty) App.audio.playSongs(tape.songs, from: tape.shownName, tape: tape.name);
  }
}
