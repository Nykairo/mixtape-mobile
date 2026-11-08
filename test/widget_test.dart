// Mixtape's own checks, run by `flutter test` (and by the build on GitHub before every release).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/account.dart';
import 'package:mixtape/audio.dart' show QueueOrder;
import 'package:mixtape/cassette.dart';
import 'package:mixtape/library.dart';
import 'package:mixtape/look.dart';
import 'package:mixtape/model.dart';
import 'package:mixtape/store.dart';

/// An account that keeps its tapes and library in memory instead of on the server.
class FakeAccount extends Account {
  FakeAccount() {
    session = Session(uid: 'u1', username: 'tester', display: 'Tester', access: 'a', refresh: 'r', expires: 9e12);
  }

  final rows = <String, Map<String, Object?>>{}; // name -> {data, deleted, updated_at}
  Map<String, Object?> library = {};
  int clock = 0;
  int pushes = 0;

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
}

Map<String, Object?> song(String ref, [String title = '']) =>
    {'id': 'yt$ref', 'src': 'yt', 'ref': ref, 'title': title.isEmpty ? ref : title, 'artist': 'A', 'art': '', 'dur': 200};

void main() {
  setUpAll(() async {
    await Store.open(at: Directory.systemTemp.createTempSync('mixtape-test'));
  });

  group('songs and tapes', () {
    test('a song keeps what the computer wrote about it', () {
      final t = Track.fromJson({...song('abc'), 'album': 'Blue', 'album_id': 'MPRE1'})!;
      expect(t.id, 'ytabc');
      expect(t.album, 'Blue');
      expect(t.toJson()['album_id'], 'MPRE1');
      expect(Track.fromJson({'title': 'no source'}), isNull);
    });

    test('a tape goes to the account and back the same', () {
      final data = {
        'songs': [song('a'), song('b')],
        'note': 'road trip',
        'paper': 4,
        'design': {'shell': 'clear', 'items': []},
        'future_key': 1,
      };
      final tape = Tape.fromJson('Summer', data);
      expect(tape.songs.length, 2);
      expect(tape.paper, 4);
      expect(fingerprint(tape.toJson()), fingerprint(Tape.fromJson('Summer', tape.toJson()).toJson()));
      expect(tape.toJson()['future_key'], 1);
    });

    test('the label paper comes from the name the way the desktop picks it', () {
      expect(crc32('123456789'.codeUnits), 0xCBF43926); // the CRC-32 check value
      expect(slotFor('Liked songs'), inInclusiveRange(0, 5));
    });

    test('tape lengths and clocks', () {
      expect(tapeFor(45 * 60), 'C46');
      expect(tapeFor(61 * 60), 'C90');
      expect(clock(65), '1:05');
      expect(clock(3725), '1:02:05');
      expect(fingerprint({'b': 1, 'a': 2}), fingerprint({'a': 2, 'b': 1}));
    });

    test('grouped tapes show their own name', () {
      expect(Tape(name: 'Podcast: Late Show').shownName, 'Late Show');
      expect(Tape(name: 'Podcast: Late Show').group, 'Podcast');
      expect(Tape(name: 'Road: trip').group, isNull);
    });
  });

  group('in step with the account', () {
    test('tapes come in, changes go up, deletes travel', () async {
      final acc = FakeAccount();
      acc.serverPut('Mix', {
        'songs': [song('1')],
        'note': '',
        'paper': null,
        'design': null,
      });
      final lib = Library(acc);
      await lib.sync();
      expect(lib.tapes.keys, ['Mix']);
      expect(lib.tapes['Mix']!.songs.map((t) => t.ref), ['1']);
      expect(acc.pushes, 0, reason: 'nothing changed here, nothing goes up');

      lib.addTo(lib.tapes['Mix']!, [Track.fromJson(song('2'))!]);
      await lib.sync();
      final up = acc.rows['Mix']!['data'] as Map;
      expect((up['songs'] as List).length, 2);

      acc.serverPut('Mix', const {}, deleted: true); // deleted on the computer
      await lib.sync();
      expect(lib.tapes.containsKey('Mix'), isFalse);
      lib.dispose();
    });

    test('a tape changed on both sides keeps the phone\'s version', () async {
      final acc = FakeAccount();
      acc.serverPut('Both', {
        'songs': [song('1')],
      });
      final lib = Library(acc);
      await lib.sync();
      lib.addTo(lib.tapes['Both']!, [Track.fromJson(song('phone'))!]);
      acc.serverPut('Both', {
        'songs': [song('1'), song('computer')],
      });
      await lib.sync();
      expect(lib.tapes['Both']!.songs.map((t) => t.ref), ['1', 'phone']);
      expect(((acc.rows['Both']!['data'] as Map)['songs'] as List).length, 2);
      lib.dispose();
    });

    test('liked songs from both sides come together', () async {
      final acc = FakeAccount();
      acc.library = {
        'liked': [song('x')],
        'other': 'kept',
      };
      final lib = Library(acc);
      lib.toggleLike(Track.fromJson(song('y'))!);
      await lib.sync();
      expect(lib.liked.map((t) => t.ref).toSet(), {'x', 'y'});
      expect((acc.library['liked'] as List).length, 2);
      expect(acc.library['other'], 'kept', reason: "what the phone doesn't know stays");

      // unliked on the computer: it goes here too
      acc.library = {
        'liked': [song('y')],
        'other': 'kept',
      };
      await lib.sync();
      expect(lib.liked.map((t) => t.ref), ['y']);
      lib.dispose();
    });
  });

  group('shuffle order', () {
    test('play next goes right after the song that plays, add to queue at the end', () {
      final o = QueueOrder()..insert(0, 5);
      o.shuffle(initialIndex: 3);
      expect(o.indices.first, 3);
      expect(o.indices.toSet(), {0, 1, 2, 3, 4});
      final playing = o.indices.first;
      o.after = playing; // "Play next" puts a song in at index 4 (right after 3 in the queue)
      o.insert(4, 1);
      o.after = null;
      expect(o.indices[0], 3);
      expect(o.indices[1], 4, reason: 'the new song is next in the shuffled order');
      expect(o.indices.toSet(), {0, 1, 2, 3, 4, 5});
      o.insert(6, 1); // "Add to queue"
      expect(o.indices.last, 6);
      o.removeRange(4, 5);
      expect(o.indices.toSet(), {0, 1, 2, 3, 4, 5});
      expect(o.indices.first, 3);
    });
  });

  testWidgets('a cassette draws, with and without decorations', (tester) async {
    for (final design in <Map<String, Object?>?>[
      null,
      {'shell': 'clear', 'finish': 'glitter', 'stripes': 'fade', 'pen': 'marker', 'screws': 'gold', 'hub': 'red'},
      {'shell': 'white', 'finish': 'gloss', 'stripes': 'none', 'pen': 'type', 'corner_color': 'blue'},
    ]) {
      await tester.pumpWidget(MaterialApp(
        theme: Look.theme(),
        home: Center(
          child: SizedBox(
            width: 320,
            child: Cassette(title: 'Road trip', design: design, sticky: 'hi!', leftNote: 'C60', rightNote: '12 songs', playing: true),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink()); // the reels stop with it
  });
}
