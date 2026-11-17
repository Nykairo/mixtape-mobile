// Every page of the app on the phones people have, one phone per run:
//   flutter test --dart-define=PHONE=galaxy_s24 test/devices_test.dart
// Each phone comes with its screen, its status bar on top and its keys or gesture bar at the bottom.
// Every scene is checked for words lying on other words, buttons on top of each other, anything under
// those bars and anything that ran out of room (see layout_check.dart). What turns up goes to
// test/goldens/devices/<phone>/problems.txt, and with --dart-define=PICTURES=true --update-goldens
// every scene is saved next to it, the bars drawn in.

@Tags(['devices'])
@Timeout(Duration(minutes: 12))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/app.dart';
import 'package:mixtape/rooms.dart' as rooms;
import 'package:mixtape/ui/now_playing.dart';
import 'package:mixtape/ui/pages.dart';
import 'package:mixtape/ui/profile_page.dart';
import 'package:mixtape/ui/settings_page.dart';
import 'package:mixtape/ui/shell.dart';
import 'package:mixtape/ui/sign_in.dart';
import 'package:mixtape/ui/stats_page.dart';
import 'package:mixtape/ui/studio.dart';
import 'package:mixtape/ui/tape_page.dart';
import 'package:mixtape/ui/together_page.dart';
import 'package:mixtape/ui/widgets.dart';

import 'box.dart';
import 'layout_check.dart';

/// A phone: its screen in logical pixels, the status bar's height and what sits at the bottom (three
/// keys, or the thin gesture bar).
class Phone {
  const Phone(this.size, this.top, this.bottom, {this.keys = true});

  final Size size;
  final double top;
  final double bottom;
  final bool keys;
}

const phones = {
  'galaxy_s24': Phone(Size(384, 832), 36, 48), // One UI's three keys, the way Samsung ships it
  'galaxy_a55': Phone(Size(411, 891), 32, 48),
  'pixel_8': Phone(Size(412, 915), 48, 24, keys: false),
  'small': Phone(Size(360, 640), 24, 48),
  'iphone_15': Phone(Size(393, 852), 59, 34, keys: false),
  'iphone_se': Phone(Size(375, 667), 20, 0, keys: false),
  'fold_cover': Phone(Size(344, 882), 36, 48), // the Galaxy Z Fold's narrow outer screen
  'tablet': Phone(Size(800, 1280), 28, 48),
};

const phoneName = String.fromEnvironment('PHONE', defaultValue: 'galaxy_s24');
final Phone phone = phones[phoneName]!;
final _found = <String>[];

BuildContext inside(WidgetTester tester) => tester.element(find.byType(Shell, skipOffstage: false));

/// The status bar and the keys at the bottom, drawn over the app the way the phone draws them.
Widget _bars(BuildContext context, Widget? child) {
  const ink = Color(0xF0FFFFFF);
  return Stack(children: [
    child ?? const SizedBox.shrink(),
    Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: phone.top,
      child: IgnorePointer(
        child: Container(
          color: const Color(0x33000000),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.bottomCenter,
          child: const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Text('20:48', style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
              Spacer(),
              Icon(Icons.signal_cellular_alt_rounded, color: ink, size: 14),
              SizedBox(width: 4),
              Icon(Icons.battery_5_bar_rounded, color: ink, size: 14),
            ]),
          ),
        ),
      ),
    ),
    if (phone.bottom > 0)
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: phone.bottom,
        child: IgnorePointer(
          child: Container(
            color: const Color(0x33000000),
            alignment: Alignment.center,
            child: phone.keys
                ? const Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    Icon(Icons.menu_rounded, color: ink, size: 18),
                    Icon(Icons.crop_square_rounded, color: ink, size: 18),
                    Icon(Icons.arrow_back_ios_new_rounded, color: ink, size: 16),
                  ])
                : Container(width: 120, height: 4, decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(2))),
          ),
        ),
      ),
  ]);
}

Future<void> start(WidgetTester tester, {Size? size}) => pumpApp(tester,
    size: size ?? phone.size,
    bars: EdgeInsets.only(top: phone.top, bottom: phone.bottom),
    builder: pictures ? _bars : null);

/// Looks at the scene: what ran out of room (Flutter says so with an exception), and what looks wrong.
Future<void> look(WidgetTester tester, String scene) async {
  await wait(tester);
  final thrown = tester.takeException();
  if (thrown != null) _found.add('$scene: ${'$thrown'.split('\n').first}');
  for (final p in layoutProblems(tester)) {
    _found.add('$scene: $p');
  }
  if (pictures) {
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/devices/$phoneName/$scene.png'));
  }
}

/// Scrolls the page that shows by a part of the screen's height.
Future<void> scroll(WidgetTester tester, double part) async {
  final lists = find.byType(Scrollable).hitTestable();
  if (lists.evaluate().isEmpty) return;
  await tester.drag(lists.first, Offset(0, -phone.size.height * part));
  await wait(tester);
}

Future<bool> tapText(WidgetTester tester, String text) async {
  final f = find.text(text).hitTestable();
  if (f.evaluate().isEmpty) return false;
  await tester.tap(f.first);
  await wait(tester);
  return true;
}

void main() {
  setUpAll(() async {
    await loadFonts();
    await Box.open();
  });
  setUp(quietPlugins);
  tearDownAll(() {
    final out = File('test/goldens/devices/$phoneName/problems.txt')..createSync(recursive: true);
    out.writeAsStringSync(_found.isEmpty ? 'nothing\n' : '${_found.join('\n')}\n');
    debugPrint('${_found.length} problems on $phoneName');
    for (final f in _found) {
      debugPrint('  $f');
    }
  });

  testWidgets('Home', (tester) async {
    await start(tester);
    await look(tester, 'home');
    await scroll(tester, 0.75);
    await look(tester, 'home_2');
    await scroll(tester, 0.9);
    await look(tester, 'home_3');
    await scroll(tester, 0.9);
    await look(tester, 'home_4');
    await close(tester);
  });

  testWidgets('Search', (tester) async {
    await start(tester);
    Shell.goTo(2);
    await look(tester, 'search');
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await look(tester, 'search_recent');
    await tester.enterText(find.byType(TextField), 'daft');
    await tester.pump(const Duration(milliseconds: 300));
    await look(tester, 'search_typing');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await look(tester, 'search_results');
    await scroll(tester, 0.7);
    await look(tester, 'search_results_2');
    if (await tapText(tester, 'Songs')) await look(tester, 'search_songs');
    if (await tapText(tester, 'Albums')) await look(tester, 'search_albums');
    if (await tapText(tester, 'Artists')) await look(tester, 'search_artists');
    if (await tapText(tester, 'Videos')) await look(tester, 'search_videos');
    await close(tester);
  });

  testWidgets('Artist and album', (tester) async {
    await start(tester);
    Shell.push(const ArtistView(id: 'UCRr1xG_2WIDs18a6cIiCxeA', name: 'Daft Punk'));
    await look(tester, 'artist');
    await scroll(tester, 0.7);
    await look(tester, 'artist_2');
    await scroll(tester, 0.8);
    await look(tester, 'artist_3');
    Shell.push(const AlbumView(id: 'MPREb_K8qWMWVqXGi', title: 'Random Access Memories'));
    await look(tester, 'album');
    await scroll(tester, 0.7);
    await look(tester, 'album_2');
    await close(tester);
  });

  testWidgets('Library', (tester) async {
    await start(tester);
    Shell.goTo(3);
    await look(tester, 'library');
    await tester.tap(find.byTooltip('As cassettes'));
    await look(tester, 'library_cassettes');
    await tester.tap(find.byTooltip('As a list'));
    await wait(tester);
    if (await tapText(tester, 'On the phone')) await look(tester, 'library_phone');
    await close(tester);
  });

  testWidgets('Tapes', (tester) async {
    await start(tester);
    Shell.push(TapePage(tape: App.library.tapes['Road trip']!));
    await look(tester, 'tape');
    await scroll(tester, 0.6);
    await look(tester, 'tape_2');
    Shell.push(TapePage(tape: App.library.tapes['Night drive']!));
    await look(tester, 'tape_night_drive');
    Shell.push(const TapePage.liked());
    await look(tester, 'liked');
    await close(tester);
  });

  testWidgets('Menus and the tape studio', (tester) async {
    await start(tester);
    unawaited(songMenu(inside(tester), Box.songs[2]));
    await look(tester, 'song_menu');
    Navigator.of(inside(tester), rootNavigator: true).pop();
    await wait(tester);
    unawaited(StudioPage.open(inside(tester), App.library.tapes['Night drive']!));
    await look(tester, 'studio');
    // the sticker sheet, a sticker on the tape with everything it can do, the other tabs, and leaving
    // without Done
    if (await tapText(tester, 'Sticker')) {
      await look(tester, 'sticker_sheet');
      final cells = find.byType(Tooltip).hitTestable();
      if (cells.evaluate().isNotEmpty) {
        await tester.tap(cells.first);
        await look(tester, 'studio_sticker');
        await scroll(tester, 0.5);
        await look(tester, 'studio_sticker_2');
      }
    }
    for (final tab in ['SHELL', 'LABEL', 'REELS', 'NOTE']) {
      await tapText(tester, tab);
      await look(tester, 'studio_${tab.toLowerCase()}');
    }
    await tester.binding.handlePopRoute();
    await wait(tester);
    await tester.binding.handlePopRoute();
    await look(tester, 'studio_leave');
    await close(tester);
  });

  testWidgets('Stats and Rewind', (tester) async {
    await start(tester);
    Shell.push(const StatsPage());
    await look(tester, 'stats');
    await scroll(tester, 0.7);
    await look(tester, 'stats_2');
    await scroll(tester, 0.8);
    await look(tester, 'stats_3');
    unawaited(RewindPage.open(inside(tester), 'year'));
    await look(tester, 'rewind_1');
    for (var card = 2; card <= 12 && find.text('Share the card').evaluate().isEmpty; card++) {
      await tester.tapAt(Offset(phone.size.width * 0.8, phone.size.height * 0.58));
      await tester.pump(const Duration(milliseconds: 500));
      await look(tester, 'rewind_$card');
    }
    await close(tester);
  });

  testWidgets('Settings and signing in', (tester) async {
    await start(tester);
    Shell.push(const SettingsPage());
    await look(tester, 'settings');
    await scroll(tester, 0.7);
    await look(tester, 'settings_2');
    await scroll(tester, 0.8);
    await look(tester, 'settings_3');
    unawaited(SignInPage.open(inside(tester)));
    await look(tester, 'sign_in');
    await close(tester);
  });

  testWidgets('Together', (tester) async {
    Box.account.waiting = [
      {'sender': 'u2', 'code': 'KX72PQ', 'kind': 'party', 'room_name': 'Anna’s birthday', 'at': '2026-11-15T10:00:00Z'},
    ];
    Box.account.known = {
      'u2': {'id': 'u2', 'username': 'anna', 'display_name': 'Anna', 'color': ''},
    };
    await start(tester);
    unawaited(TogetherPage.open(inside(tester)));
    await look(tester, 'together');
    await scroll(tester, 0.6);
    await look(tester, 'together_2');

    final t = App.together;
    t.friend = 'u2';
    t.friendName = 'Anna';
    t.friendNow = {...Box.songs[3].toJson(), 'playing': true};
    t.notifyListeners();
    await look(tester, 'together_along');

    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    t.friend = '';
    t.friendName = '';
    t.friendNow = null;
    t.room = {'code': 'KX72PQ', 'kind': 'room', 'name': 'Friday night', 'role': 'host'};
    t.state = rooms.apply(rooms.blank(), [
      rooms.add('anna', now, [
        for (final s in Box.songs.take(5)) {'k': rooms.newKey(), 't': s.toJson(), 'by': 'anna'},
      ]),
    ]);
    t.members = [
      {'member': 'u1', 'role': 'host', 'profile': {'id': 'u1', 'username': 'tester', 'display_name': 'Tester'}},
      {'member': 'u2', 'role': 'guest', 'profile': {'id': 'u2', 'username': 'anna', 'display_name': 'Anna'}},
      {'member': 'u3', 'role': 'guest', 'profile': {'id': 'u3', 'username': 'ben', 'display_name': ''}},
    ];
    t.here = {
      'u1': {'user': 'tester', 'name': 'Tester'},
      'u2': {'user': 'anna', 'name': 'Anna'},
    };
    t.notifyListeners();
    await look(tester, 'together_room');
    await scroll(tester, 0.6);
    await look(tester, 'together_room_2');

    t.room = {'code': 'KX72PQ', 'kind': 'party', 'name': 'Friday night', 'role': 'host'};
    t.requests = [
      {'id': 1, 'member': 'u2', 'song': Box.songs[9].toJson(), 'at': '2026-11-15T10:00:00Z'},
    ];
    t.notifyListeners();
    await look(tester, 'together_party');
    await scroll(tester, 0.6);
    await look(tester, 'together_party_2');

    t.room = null;
    t.state = rooms.blank();
    t.members = [];
    t.requests = [];
    t.here = {};
    t.notifyListeners();
    Box.account.waiting = [];
    await close(tester);
  });

  testWidgets('Profiles', (tester) async {
    Box.account.cards = {
      'anna': {
      'id': 'u2',
      'username': 'anna',
      'display_name': 'Anna',
      'pronouns': 'she/her',
      'bio': 'Tapes for long drives.\nAlways one more song.',
      'color': '#39d0a0',
      'avatar': '',
      'anthem': Box.songs[3].toJson(),
      'showcase': {
        'name': 'Night drive',
        'paper': 2,
        'design': const {},
        'songs': [for (final t in Box.songs.take(4)) t.toJson()],
        'count': 12,
      },
      'top_artists': ['Kavinsky', 'M83', 'The Midnight'],
      'share_listening': true,
      'updated_at': '2026-11-15T10:00:00Z',
    },
      'tester': {'id': 'u1', 'username': 'tester', 'display_name': 'Tester', 'updated_at': '2026-11-15T10:00:00Z'},
    };
    await start(tester);
    ProfilePage.open('anna');
    await look(tester, 'profile');
    await tester.pageBack();
    await tester.pumpAndSettle();
    ProfilePage.open('tester');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit your profile'));
    await look(tester, 'profile_edit');
    await scroll(tester, 0.7);
    await look(tester, 'profile_edit_2');
    Box.account.cards = {};
    await close(tester);
  });

  testWidgets('Together, signed out', (tester) async {
    final mine = Box.account.session;
    Box.account.session = null;
    addTearDown(() => Box.account.session = mine);
    await start(tester);
    unawaited(TogetherPage.open(inside(tester)));
    await look(tester, 'together_signed_out');
    await close(tester);
  });

  testWidgets('Samples', (tester) async {
    await start(tester);
    await tester.runAsync(() async {
      await App.samples.more().timeout(const Duration(seconds: 20));
      if (App.samples.items.isNotEmpty) await App.samples.show(0).timeout(const Duration(seconds: 20));
    });
    Shell.goTo(1);
    await look(tester, 'samples');
    Shell.goTo(0);
    await wait(tester, rounds: 12);
    await close(tester);
  });

  testWidgets('The player', (tester) async {
    await start(tester);
    await Box.startMusic(tester);
    await look(tester, 'home_playing');
    NowPlaying.view = 'cover';
    unawaited(NowPlaying.open(inside(tester)));
    await look(tester, 'player');
    if (await tapText(tester, 'Tape')) await look(tester, 'player_tape');
    await tapText(tester, 'Song');
    if (await tapText(tester, 'UP NEXT')) await look(tester, 'player_queue');
    final lyrics = find.text('LYRICS').hitTestable();
    if (lyrics.evaluate().isNotEmpty) {
      await tester.tap(lyrics.last);
      await look(tester, 'player_lyrics');
    }
    final related = find.text('RELATED').hitTestable();
    if (related.evaluate().isNotEmpty) {
      await tester.tap(related.last);
      await look(tester, 'player_related');
    }
    await close(tester);
  });

  testWidgets("The player's sheets", (tester) async {
    await start(tester);
    await Box.startMusic(tester);
    NowPlaying.view = 'cover';
    unawaited(NowPlaying.open(inside(tester)));
    await wait(tester);
    final more = find.byTooltip('More').hitTestable();
    if (more.evaluate().isNotEmpty) {
      await tester.tap(more.first);
      await look(tester, 'player_more');
      Navigator.of(inside(tester), rootNavigator: true).pop();
      await wait(tester);
    }
    if (await tapText(tester, 'Sleep')) {
      await look(tester, 'player_sleep');
      Navigator.of(inside(tester), rootNavigator: true).pop();
      await wait(tester);
    }
    if (await tapText(tester, '1×')) {
      await look(tester, 'player_speed');
      Navigator.of(inside(tester), rootNavigator: true).pop();
      await wait(tester);
    }
    await close(tester);
  });
}
