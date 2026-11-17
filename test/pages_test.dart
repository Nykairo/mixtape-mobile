// Every page of the app opened once, with the app in its box (box.dart): nothing may throw or run out
// of room, and what matters on each page has to be there. A run with
//   flutter test --dart-define=PICTURES=true --update-goldens test/pages_test.dart
// also saves a picture of every scene to test/goldens, to look at.

@Timeout(Duration(minutes: 4))
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/app.dart';
import 'package:mixtape/cassette.dart';
import 'package:mixtape/decor.dart';
import 'package:mixtape/rooms.dart' as rooms;
import 'package:mixtape/ui/now_playing.dart';
import 'package:mixtape/ui/pages.dart';
import 'package:mixtape/ui/profile_page.dart';
import 'package:mixtape/ui/settings_page.dart';
import 'package:mixtape/ui/shell.dart';
import 'package:mixtape/ui/stats_page.dart';
import 'package:mixtape/ui/studio.dart';
import 'package:mixtape/ui/tape_page.dart';
import 'package:mixtape/ui/together_page.dart';
import 'package:mixtape/ui/widgets.dart';

import 'box.dart';

/// A place in the app to open pages from, the way a tap inside it would. (Also while a page covers
/// the whole screen, which takes the Shell off the stage.)
BuildContext inside(WidgetTester tester) => tester.element(find.byType(Shell, skipOffstage: false));

void main() {
  setUpAll(() async {
    await loadFonts();
    await Box.open();
  });
  setUp(quietPlugins);

  testWidgets('Home: shortcuts, quick picks, the tapes and the shelves from YouTube Music', (tester) async {
    await pumpApp(tester);
    expect(find.text('MIXTAPE'), findsOneWidget);
    expect(find.text('Your tapes'), findsOneWidget);
    expect(find.text('Road trip'), findsWidgets);
    expect(find.text('Quick picks'), findsOneWidget, reason: 'the radio of what played lately came in');
    await shot(tester, 'home');
    await tester.dragFrom(const Offset(206, 560), const Offset(0, -760));
    await wait(tester);
    await shot(tester, 'home_further');
    await tester.dragFrom(const Offset(206, 560), const Offset(0, -900));
    await wait(tester);
    await shot(tester, 'home_shelves');
    await close(tester);
  });

  testWidgets('Search: moods to browse, what was searched, suggestions, results and their filters', (tester) async {
    await pumpApp(tester);
    Shell.goTo(2);
    await wait(tester);
    expect(find.text('Browse all'), findsOneWidget);
    await shot(tester, 'search');

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('get lucky'), findsOneWidget);
    await shot(tester, 'search_recent');

    await tester.enterText(find.byType(TextField), 'daft');
    await tester.pump(const Duration(milliseconds: 300));
    await wait(tester);
    expect(find.byTooltip('Fill in'), findsWidgets, reason: 'words to search for are offered');
    await shot(tester, 'search_typing');

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await wait(tester);
    expect(find.text('Daft Punk'), findsWidgets);
    expect(find.text('Random Access Memories'), findsWidgets);
    await shot(tester, 'search_results');

    await tester.tap(find.text('Songs'));
    await wait(tester);
    expect(find.textContaining('Arena'), findsWidgets);
    await shot(tester, 'search_songs');
    await tester.tap(find.text('Albums'));
    await wait(tester);
    await shot(tester, 'search_albums');
    await close(tester);
  });

  testWidgets('An artist and an album from YouTube Music', (tester) async {
    await pumpApp(tester);
    Shell.push(const ArtistView(id: 'UCRr1xG_2WIDs18a6cIiCxeA', name: 'Daft Punk'));
    await wait(tester);
    expect(find.text('Daft Punk'), findsWidgets);
    await shot(tester, 'artist');
    await tester.dragFrom(const Offset(206, 560), const Offset(0, -620));
    await wait(tester);
    await shot(tester, 'artist_further');

    Shell.push(const AlbumView(id: 'MPREb_K8qWMWVqXGi', title: 'Random Access Memories'));
    await wait(tester);
    expect(find.text('Random Access Memories'), findsWidgets);
    await shot(tester, 'album');
    await close(tester);
  });

  testWidgets('The library: as a list, as cassettes, what is on the phone', (tester) async {
    await pumpApp(tester);
    Shell.goTo(3);
    await wait(tester);
    expect(find.text('Your Library'), findsOneWidget);
    expect(find.text('Night drive'), findsOneWidget);
    expect(find.text('Liked songs'), findsOneWidget);
    await shot(tester, 'library');

    await tester.tap(find.byTooltip('As cassettes'));
    await wait(tester);
    expect(find.text('Night drive'), findsOneWidget);
    await shot(tester, 'library_cassettes');
    await tester.tap(find.byTooltip('As a list'));
    await wait(tester);

    await tester.tap(find.text('On the phone'));
    await wait(tester);
    expect(find.text('Songs on the phone'), findsOneWidget);
    await shot(tester, 'library_phone');
    await tester.tap(find.text('On the phone'));
    await close(tester);
  });

  testWidgets('A tape and the liked songs', (tester) async {
    await pumpApp(tester);
    Shell.push(TapePage(tape: App.library.tapes['Road trip']!));
    await wait(tester);
    expect(find.text('Road trip'), findsWidgets);
    expect(find.text(Box.songs.first.title), findsWidgets);
    await shot(tester, 'tape');
    await tester.dragFrom(const Offset(206, 560), const Offset(0, -400));
    await wait(tester);
    await shot(tester, 'tape_songs');

    Shell.push(const TapePage.liked());
    await wait(tester);
    expect(find.text('Liked songs'), findsWidgets);
    await shot(tester, 'liked');
    await close(tester);
  });

  testWidgets("A song's menu and the tape studio", (tester) async {
    await pumpApp(tester);
    unawaited(songMenu(inside(tester), Box.songs[2]));
    await wait(tester);
    expect(find.text('Play next'), findsOneWidget);
    await shot(tester, 'song_menu');
    Navigator.of(inside(tester), rootNavigator: true).pop();
    await wait(tester);

    unawaited(StudioPage.open(inside(tester), App.library.tapes['Night drive']!));
    await wait(tester);
    expect(find.text('Tape studio'), findsOneWidget);
    await shot(tester, 'studio');
    await close(tester);
  });

  testWidgets('Decorating a tape: moving a label, a sticker, a note, the pen, undo, and Done', (tester) async {
    await pumpApp(tester);
    final tape = App.library.tapes['Night drive']!;
    unawaited(StudioPage.open(inside(tester), tape));
    await wait(tester);
    expect(find.text('DECOR'), findsOneWidget);
    expect(find.text('Surprise me'), findsOneWidget);
    expect(find.text('Take all off'), findsOneWidget, reason: 'the computer stuck things on this tape');
    await shot(tester, 'studio_decor');

    // the label the computer stuck on, picked with a tap and dragged to the right
    final cassette = tester.getRect(find.byType(Cassette));
    final label = Offset(cassette.left + cassette.width * 0.5, cassette.top + cassette.height * 0.74);
    await tester.tapAt(label);
    await wait(tester);
    expect(find.text('Change the words'), findsOneWidget);
    await tester.dragFrom(label, const Offset(36, -10));
    await wait(tester);
    await shot(tester, 'studio_label');
    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await wait(tester);

    // a sticker from the sheet, made holo
    await tester.tap(find.text('Sticker'));
    await wait(tester);
    expect(find.text('Stickers'), findsOneWidget);
    await shot(tester, 'sticker_sheet');
    await tester.tap(find.byTooltip(StickerSheet.the!.nameOf('vinyl')));
    await wait(tester);
    expect(find.text('Swap sticker'), findsOneWidget);
    await tester.tap(find.byTooltip('Holo'));
    await wait(tester);
    await shot(tester, 'studio_sticker');
    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await wait(tester);

    // a sticky note, written on right away
    await tester.tap(find.text('Sticky note'));
    await wait(tester);
    final ask = find.byType(AlertDialog);
    expect(ask, findsOneWidget);
    await tester.enterText(find.descendant(of: ask, matching: find.byType(TextField)), 'turn it up');
    await tester.tap(find.descendant(of: ask, matching: find.text('Done')));
    await wait(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await wait(tester);

    // a line with the pen, taken back with undo
    await tester.tap(find.text('Pen'));
    await wait(tester);
    expect(find.text('Done drawing'), findsOneWidget);
    await tester.dragFrom(cassette.center + const Offset(-50, 6), const Offset(100, -24));
    await wait(tester);
    await shot(tester, 'studio_pen');
    await tester.tap(find.text('Done drawing'));
    await wait(tester);
    await tester.tap(find.byTooltip('Undo'));
    await wait(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    for (var k = 0; k < 40 && App.library.layerOf(tape) == null; k++) {
      await wait(tester, rounds: 1);
    }
    await wait(tester);
    expect(find.text('Tape studio'), findsNothing);
    final items = [for (final it in tape.design!['items'] as List) Map<String, Object?>.from(it as Map)];
    expect(items.length, Box.decorations.length + 2, reason: 'a sticker and a note more, the line taken back');
    expect(items.where((it) => it['kind'] == 'ink').length, 1);
    expect(items.any((it) => it['shape'] == 'vinyl' && it['finish'] == 'holo'), isTrue);
    expect(items.any((it) => it['kind'] == 'note' && it['text'] == 'turn it up'), isTrue);
    expect(items.firstWhere((it) => it['kind'] == 'dymo')['x'] as double, greaterThan(0.55));
    expect(App.library.layerOf(tape), isNotNull, reason: 'the phones get a drawing of it all');

    // the drawing goes to the account with the tape, so the other phones have it too
    await tester.runAsync(() => App.library.sync());
    expect(Box.account.pictures.containsKey(tape.design!['layer']), isTrue);
    await close(tester);
  });

  testWidgets('Stats, and Rewind card by card', (tester) async {
    await pumpApp(tester);
    Shell.push(const StatsPage());
    await wait(tester);
    expect(find.text('Your listening'), findsOneWidget);
    expect(find.text('Top songs'), findsOneWidget);
    expect(find.text('MINUTES LISTENED'), findsOneWidget);
    await shot(tester, 'stats');
    await tester.dragFrom(const Offset(206, 560), const Offset(0, -700));
    await wait(tester);
    await shot(tester, 'stats_further');

    unawaited(RewindPage.open(inside(tester), 'year'));
    await wait(tester);
    expect(find.text('on Mixtape'), findsOneWidget);
    await shot(tester, 'rewind_1');
    // card after card, up to the J-card at the end, which stays
    for (var card = 2; card <= 12 && find.text('Share the card').evaluate().isEmpty; card++) {
      await tester.tapAt(const Offset(330, 520));
      await tester.pump(const Duration(milliseconds: 500));
      await wait(tester, rounds: 2);
      await shot(tester, 'rewind_$card');
    }
    expect(find.text('Share the card'), findsOneWidget, reason: 'Rewind ends on the J-card');
    expect(find.byType(JCard), findsOneWidget);
    await close(tester);
  });

  testWidgets('Settings', (tester) async {
    await pumpApp(tester);
    Shell.push(const SettingsPage());
    await wait(tester);
    expect(find.text('Radio'), findsOneWidget);
    expect(find.text('Crossfade'), findsOneWidget);
    await shot(tester, 'settings');
    // further down the list, past what's between songs and the lyrics
    await tester.scrollUntilVisible(find.textContaining('5 songs'), 300, scrollable: find.byType(Scrollable).first);
    await wait(tester);
    expect(find.text('Friends can listen along'), findsOneWidget);
    expect(find.textContaining('5 songs'), findsOneWidget, reason: 'the songs saved on the phone are counted');
    await shot(tester, 'settings_further');
    await close(tester);
  });

  testWidgets('Together: the ways in, listening along, a room and a party', (tester) async {
    Box.account.waiting = [
      {'sender': 'u2', 'code': 'KX72PQ', 'kind': 'party', 'room_name': 'Anna’s birthday', 'at': '2026-11-15T10:00:00Z'},
    ];
    Box.account.known = {
      'u2': {'id': 'u2', 'username': 'anna', 'display_name': 'Anna', 'color': ''},
    };
    await pumpApp(tester);
    unawaited(TogetherPage.open(inside(tester)));
    await wait(tester);
    expect(find.text('Listen along'), findsOneWidget);
    expect(find.text('Anna invites you'), findsOneWidget);
    await shot(tester, 'together');

    final t = App.together;
    t.friend = 'u2';
    t.friendName = 'Anna';
    t.friendNow = {...Box.songs[3].toJson(), 'playing': true};
    t.notifyListeners();
    await wait(tester);
    expect(find.text('LISTENING ALONG WITH'), findsOneWidget);
    await shot(tester, 'together_along');

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
    await wait(tester);
    expect(find.text('ROOM  ·  YOU HOST'), findsOneWidget);
    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.text('Anna added a song'), findsOneWidget);
    await shot(tester, 'together_room');

    t.room = {'code': 'KX72PQ', 'kind': 'party', 'name': 'Friday night', 'role': 'host'};
    t.requests = [
      {'id': 1, 'member': 'u2', 'song': Box.songs[9].toJson(), 'at': '2026-11-15T10:00:00Z'},
    ];
    t.notifyListeners();
    await wait(tester);
    expect(find.text('ASKED FOR'), findsOneWidget);
    expect(find.text('Take requests'), findsOneWidget);
    expect(find.text('End the party'), findsOneWidget);
    t.reactions.add('heart');
    t.reactions.add('flame');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byIcon(Icons.local_fire_department_rounded), findsWidgets);
    await shot(tester, 'together_party');
    await tester.pump(const Duration(seconds: 4)); // the reactions float away

    t.room = null;
    t.state = rooms.blank();
    t.members = [];
    t.requests = [];
    t.here = {};
    t.notifyListeners();
    Box.account.waiting = [];
    await close(tester);
  });

  testWidgets("Profiles: somebody's, and yours to change", (tester) async {
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
    await pumpApp(tester);
    ProfilePage.open('anna');
    await wait(tester);
    expect(find.text('Anna'), findsWidgets);
    expect(find.text('@anna  ·  she/her'), findsOneWidget);
    expect(find.text('MY SONG'), findsOneWidget);
    expect(find.text('ON SHOW'), findsOneWidget);
    expect(find.text('Kavinsky'), findsOneWidget);
    expect(find.text('Listen along with Anna'), findsOneWidget);
    await shot(tester, 'profile');
    await tester.pageBack();
    await wait(tester);

    ProfilePage.open('tester');
    await wait(tester);
    expect(find.text('Edit your profile'), findsOneWidget);
    await tester.tap(find.text('Edit your profile'));
    await wait(tester);
    expect(find.text('Your profile'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Pronouns'), 'they/them');
    await wait(tester);
    expect(find.text('@tester  ·  they/them'), findsOneWidget, reason: 'the card shows it as it is typed');
    await shot(tester, 'profile_edit');
    await tester.tap(find.text('Save'));
    await wait(tester);
    expect(Box.account.saved?['pronouns'], 'they/them');
    Box.account.cards = {};
    await close(tester);
  });

  testWidgets('Together without an account says what it takes', (tester) async {
    final mine = Box.account.session;
    Box.account.session = null;
    addTearDown(() => Box.account.session = mine);
    await pumpApp(tester);
    unawaited(TogetherPage.open(inside(tester)));
    await wait(tester);
    expect(find.text('Music is better shared'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    await shot(tester, 'together_signed_out');
    await close(tester);
  });

  testWidgets('Samples: one song on the whole screen', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(() async {
      await App.samples.more().timeout(const Duration(seconds: 20));
      if (App.samples.items.isNotEmpty) await App.samples.show(0).timeout(const Duration(seconds: 20));
    });
    expect(App.samples.items, isNotEmpty, reason: 'the radio of the liked songs filled the feed');
    Shell.goTo(1);
    await wait(tester);
    expect(find.text('Samples'), findsWidgets);
    expect(find.text('Not for me'), findsWidgets);
    await shot(tester, 'samples');
    // leaving the tab stops the samples; that runs on both clocks, so it gets a few more rounds
    Shell.goTo(0);
    await wait(tester, rounds: 12);
    expect(App.samples.player.playing, isFalse, reason: 'Samples stops when its tab is left');
    await close(tester);
  });

  testWidgets('The player: little, big, as a tape, with its queue, lyrics and related songs', (tester) async {
    await pumpApp(tester);
    await Box.startMusic(tester);
    await wait(tester);
    expect(App.audio.current?.id, Box.songs.first.id);
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.text(Box.songs.first.title), findsWidgets);
    await shot(tester, 'home_playing');

    NowPlaying.view = 'cover';
    unawaited(NowPlaying.open(inside(tester)));
    await wait(tester);
    expect(find.text('PLAYING FROM  ROAD TRIP'), findsOneWidget);
    expect(find.text('UP NEXT'), findsOneWidget);
    await shot(tester, 'player');

    await tester.tap(find.text('Tape').first);
    await wait(tester);
    await shot(tester, 'player_tape');
    await tester.tap(find.text('Song'));
    await wait(tester);

    await tester.tap(find.text('UP NEXT'));
    await wait(tester);
    expect(find.text(Box.songs[1].title), findsWidgets, reason: 'the next song is in the queue');
    await shot(tester, 'player_queue');
    await tester.tap(find.text('LYRICS').last);
    await wait(tester);
    await shot(tester, 'player_lyrics');
    await tester.tap(find.text('RELATED').last);
    await wait(tester);
    await shot(tester, 'player_related');
    await close(tester);
  });

  testWidgets('The big player fits a small phone, and big letters', (tester) async {
    await pumpApp(tester, size: const Size(360, 640));
    await Box.startMusic(tester);
    NowPlaying.view = 'cover';
    unawaited(NowPlaying.open(inside(tester)));
    await wait(tester);
    expect(tester.takeException(), isNull);
    await shot(tester, 'player_small');
    Navigator.of(inside(tester), rootNavigator: true).pop();
    await wait(tester);

    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await wait(tester);
    expect(tester.takeException(), isNull, reason: 'Home with big letters');
    await shot(tester, 'home_big_letters');
    unawaited(NowPlaying.open(inside(tester)));
    await wait(tester);
    expect(tester.takeException(), isNull, reason: 'the player with big letters');
    await shot(tester, 'player_big_letters');
    await close(tester);
  });
}
