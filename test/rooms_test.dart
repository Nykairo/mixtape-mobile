// The rules of a room (rooms.dart), the same ones the computer has in rooms.py: what each change does to
// the room's state, and that a change made twice, or on top of somebody else's, comes out right.

import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/rooms.dart';

RoomItem item(String key, [String? id]) => {
      'k': key,
      't': {'id': 'yt${id ?? key}', 'src': 'yt', 'ref': id ?? key, 'title': 'Song $key', 'artist': 'A', 'dur': 200},
      'by': 'anna',
    };

List<String> keys(RoomState s) => [for (final it in queueOf(s)) '${it['k']}'];

void main() {
  test('the first song put into an empty room starts playing', () {
    final s = apply(blank(), [add('anna', 100, [item('a'), item('b')])]);
    expect(keys(s), ['a', 'b']);
    expect(keyOf(s), 'a');
    expect(s['paused'], isFalse);
    expect(s['did'], 'add');
    expect(position(s, 130), 30);
    expect(upcoming(s).map((it) => it['k']), ['b']);
  });

  test('added songs wait at the end, or right after the one playing', () {
    var s = apply(blank(), [add('anna', 100, [item('a'), item('b')])]);
    s = apply(s, [add('ben', 110, [item('c')])]);
    expect(keys(s), ['a', 'b', 'c']);
    expect(keyOf(s), 'a', reason: 'the song that plays keeps playing');
    s = apply(s, [add('ben', 120, [item('d')], nextUp: true)]);
    expect(keys(s), ['a', 'd', 'b', 'c']);
    s = apply(s, [add('ben', 130, [item('e')], playNow: true)]);
    expect(keys(s), ['a', 'e', 'd', 'b', 'c']);
    expect(keyOf(s), 'e');
    expect(s['did'], 'play_now');
  });

  test('a song that waits already moves up instead of coming twice', () {
    var s = apply(blank(), [add('anna', 100, [item('a'), item('b'), item('c')])]);
    s = apply(s, [add('ben', 110, [item('x', 'c')], nextUp: true)]);
    expect(keys(s), ['a', 'x', 'b']);
    // and the same change made again changes nothing
    final again = apply(s, [add('ben', 111, [item('x', 'c')], nextUp: true)]);
    expect(keys(again), keys(s));
  });

  test('pause, play and jump keep the place', () {
    var s = apply(blank(), [add('anna', 100, [item('a')])]);
    s = apply(s, [pause('ben', 140, 'a', 40)]);
    expect(s['paused'], isTrue);
    expect(position(s, 500), 40, reason: 'time stands still while paused');
    expect(pause('ben', 150, 'a', 40)(s), isFalse, reason: 'paused already');
    s = apply(s, [play('anna', 200, 'a', 40)]);
    expect(s['paused'], isFalse);
    expect(position(s, 210), 50);
    s = apply(s, [seek('anna', 220, 'a', 5)]);
    expect(position(s, 221), 6);
    expect(seek('anna', 230, 'gone', 9)(s), isFalse, reason: 'a jump meant for another song is dropped');
  });

  test('two people pressing Next at once skip one song, not two', () {
    final s = apply(blank(), [add('anna', 100, [item('a'), item('b'), item('c')])]);
    expect(skip('anna', 110, 'a', 'b')(s), isTrue);
    expect(skip('ben', 110.2, 'a', 'b')(s), isFalse);
    expect(keyOf(s), 'b');
    expect(position(s, 115), 5);
  });

  test('a song that ends hands over to the next, and the last one stops the room', () {
    var s = apply(blank(), [add('anna', 100, [item('a'), item('b')])]);
    s = apply(s, [ended('anna', 300, 'a')]);
    expect(keyOf(s), 'b');
    expect(s['did'], 'next');
    expect(ended('ben', 301, 'a')(s), isFalse, reason: 'the others report the same ending');
    s = apply(s, [ended('anna', 500, 'b')]);
    expect(s['did'], 'end');
    expect(s['paused'], isTrue);
    expect(over(s), isTrue);
    expect(said(s, 'anna'), startsWith('That was the last song'));
    // a new song starts the room again
    s = apply(s, [add('ben', 600, [item('c')])]);
    expect(keyOf(s), 'c');
    expect(over(s), isFalse);
  });

  test('taking a song out and moving one up', () {
    var s = apply(blank(), [add('anna', 100, [item('a'), item('b'), item('c'), item('d')])]);
    expect(remove('ben', 'a')(s), isFalse, reason: 'the song that plays stays: skip it instead');
    s = apply(s, [remove('ben', 'c')]);
    expect(keys(s), ['a', 'b', 'd']);
    s = apply(s, [moveNext('ben', 'd')]);
    expect(keys(s), ['a', 'd', 'b']);
    expect(moveNext('ben', 'd')(s), isFalse, reason: "it's next already");
  });

  test('a room never holds more than it should', () {
    final many = [for (var k = 0; k < most + 50; k++) item('k$k')];
    var s = apply(blank(), [add('anna', 100, many)]);
    expect(queueOf(s).length, most, reason: 'what goes over the limit is left out');
    // played songs stay for a while, then fall off the front
    for (var k = 0; k < played + 5; k++) {
      s = apply(s, [ended('anna', 200.0 + k, keyOf(s))]);
    }
    expect(indexOf(s, keyOf(s)), played);
  });

  test("what came from the server is made safe before it's used", () {
    final s = clean({
      'q': [
        item('a'),
        'nonsense',
        {'k': '', 't': {}},
        item('a'),
        {'k': 'b', 't': {'id': 'ytb', 'ref': 'b', 'title': 'B'}, 'by': 'x' * 90},
      ],
      'k': 'zzz',
      'pos': 'NaN',
      'rate': 99,
      'paused': null,
    });
    expect(keys(s), ['a', 'b']);
    expect(keyOf(s), '', reason: 'the key points at nothing in the queue');
    expect(s['pos'], 0.0);
    expect(s['rate'], 4.0);
    expect(s['paused'], isFalse, reason: 'the way the computer reads a paused that is null');
    expect(clean({'q': <Object>[]})['paused'], isTrue, reason: 'and one that is missing');
    expect('${queueOf(s)[1]['by']}'.length, 40);
    expect(clean('not a room')['q'], isEmpty);
  });

  test('what the others did, in words', () {
    var s = apply(blank(), [add('anna', 100, [item('a'), item('b')])]);
    expect(said(s, 'anna'), '', reason: 'your own changes need no words');
    expect(said(s, 'ben'), 'anna added a song');
    expect(said(s, 'ben', {'anna': 'Anna B.'}), 'Anna B. added a song');
    s = apply(s, [skip('anna', 110, 'a', 'b')]);
    expect(said(s, 'ben'), 'anna put on “Song b”');
    s = apply(s, [setRate('anna', 120, 1.25)]);
    expect(said(s, 'ben'), 'anna set the speed to 1.25×');
    expect(setRate('anna', 121, 1.25)(s), isFalse);
  });
}
