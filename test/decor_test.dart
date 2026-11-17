// What's stuck and drawn on tapes: kept by the same rules as on the computer, drawn for the phones as a
// see-through picture, and moved around in the studio.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/cassette.dart';
import 'package:mixtape/decor.dart';
import 'package:mixtape/ui/decorate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(StickerSheet.load);

  test('The sticker sheet has every sticker of the computer, in its drawers', () {
    final sheet = StickerSheet.the!;
    expect([for (final (name, _) in sheet.drawers) name], ['Music', 'Words', 'Fun', 'Nature', 'Food', 'Space']);
    expect(sheet.drawers.fold<int>(0, (n, d) => n + d.$2.length), 85);
    expect([sheet.nameOf('vinyl'), sheet.colorOf('vinyl')], ['Record', 'red']);
    expect(sheet.nameOf('nonsense'), sheet.nameOf('star'), reason: 'an unknown sticker shows as a star');
    expect(sheet.box('hifi').width, closeTo(1.1, 0.001));
    expect(sheet.box('vinyl').height, closeTo(1.06, 0.001));
  });

  test('Things on a tape are kept the way the computer keeps them', () {
    expect(cleanItem({'kind': 'confetti'}), isNull);
    expect(cleanItem('note'), isNull);
    final s = cleanItem({'kind': 'sticker', 'shape': 'star', 'x': 2, 'y': -1, 's': 9, 'rot': 1000.123, 'text': '  so   loud '})!;
    expect([s['x'], s['y'], s['s'], s['rot'], s['text']], [1.25, -0.25, 2.5, 720.0, 'so loud']);
    expect(cleanItem({'kind': 'note', 'x': true, 'y': '0.3'}), containsPair('x', 0.5));
    expect(cleanItem({'kind': 'note', 'y': '0.3'}), containsPair('y', 0.3));
    expect(cleanItem({'kind': 'dymo', 'color': 'x' * 40})!['color'], 'x' * 24);
    expect(cleanItem({'kind': 'photo'}), isNull, reason: 'a photo needs its picture');
    expect(cleanItem({'kind': 'photo', 'image': '../../etc/passwd'}), isNull);
    expect(cleanItem({'kind': 'photo', 'image': '0123456789abcdef0123.jpg'})!['image'], '0123456789abcdef0123.jpg');
    expect(
        cleanItem({
          'kind': 'ink',
          'pts': [
            [0, 0],
          ],
        }),
        isNull,
        reason: 'a line needs two points');
    final ink = cleanItem({
      'kind': 'ink',
      'w': 1,
      'pts': [
        [0, 0],
        [5, -5],
        'x',
        [1, 2, 3],
      ],
    })!;
    expect(ink['pts'], [
      [0.0, 0.0],
      [3.0, -3.0],
    ]);
    expect(ink['w'], 0.08);
    expect(cleanItems(List.filled(200, {'kind': 'note'})).length, itemLimit);
    expect(
        picturesOf([
          {'kind': 'photo', 'image': '0123456789abcdef0123.jpg'},
          {'kind': 'note', 'image': 'not a picture'},
          {'kind': 'note', 'image': 'abcdefabcdefabcdef01.png'},
        ]),
        {'0123456789abcdef0123.jpg', 'abcdefabcdefabcdef01.png'});
  });

  testWidgets('The drawing for the phones is a see-through PNG the size of the computer\'s', (tester) async {
    final png = await tester.runAsync(() => layerPng([
          {'kind': 'washi', 'x': 0.5, 'y': 0.05, 's': 0.4, 'rot': 3, 'pattern': 'grid', 'color': 'sky'},
          {'kind': 'sticker', 'shape': 'heart', 'x': 0.5, 'y': 0.5, 's': 0.2, 'rot': 0, 'finish': 'glitter'},
          {'kind': 'sticker', 'shape': 'hifi', 'x': 0.2, 'y': 0.7, 's': 0.16, 'rot': 8, 'finish': 'holo'},
          {'kind': 'dymo', 'text': 'side a', 'x': 0.5, 'y': 0.8, 's': 0.07, 'rot': 0},
          {'kind': 'note', 'text': 'hello', 'x': 0.2, 'y': 0.3, 's': 0.2, 'rot': -4},
          {'kind': 'photo', 'image': '0123456789abcdef0123.jpg', 'x': 0.8, 'y': 0.4, 's': 0.24, 'rot': 5},
          {
            'kind': 'ink',
            'x': 0.4,
            'y': 0.4,
            's': 1,
            'rot': 0,
            'w': 0.01,
            'pts': [
              [0, 0],
              [0.1, 0.05],
              [0.2, 0],
            ],
          },
        ]));
    expect(png, isNotNull);
    final head = ByteData.sublistView(png!);
    expect(head.getUint32(0), 0x89504E47, reason: 'a PNG');
    expect([head.getUint32(16), head.getUint32(20)], [900, 572]);
    expect(await tester.runAsync(() => layerPng(const [])), isNull);
  });

  test('In the studio: sticking things on, stacking them, drawing, and a full tape', () {
    final d = Decorations([]);
    var commits = 0;
    d.onCommit = () => commits++;
    expect(d.add('note'), 0);
    expect(d.current?['color'], 'yellow');
    d.add('note');
    expect(d.items[1]['color'], 'pink', reason: 'a new note takes a color the others on the tape have not');
    d.add('sticker', fields: {'shape': 'star'});
    d.restack(false);
    expect([d.sel, d.items[1]['kind']], [1, 'sticker']);
    d.turn(200);
    expect(d.current!['rot'] as double, inInclusiveRange(-180, 180));
    d.setSize(1);
    expect(d.current!['s'], itemSizes['sticker']!.$2);
    d.duplicate();
    expect(d.items.length, 4);
    d.remove();
    expect([d.items.length, d.sel], [3, -1]);

    final g = Geo(const Rect.fromLTWH(0, 0, 340, 340 / ratio));
    d.addStroke(const [Offset(100, 100), Offset(130, 120), Offset(160, 104)], g);
    final line = d.items.last;
    expect(line['kind'], 'ink');
    expect(line['x'] as double, closeTo(130 / 340, 0.001));
    expect((line['pts'] as List).length, 3);
    d.addStroke(const [Offset(50, 50)], g);
    expect((d.items.last['pts'] as List).length, 2, reason: 'a tap with the pen is a dot');

    final before = d.items.length;
    expect(d.surprise(noteShows: true), greaterThan(0));
    expect(d.items.length, greaterThan(before));
    expect(d.items.first['kind'], 'washi', reason: 'the washi tape goes under everything');
    d.clear();
    expect(d.items, isEmpty);
    for (var k = 0; k < itemLimit; k++) {
      d.add('dymo');
    }
    expect(d.full, isTrue);
    expect(d.add('note'), -1);
    expect(commits, greaterThan(itemLimit));
    d.dispose();
  });

  test('Handles stay on the canvas, apart from each other, even for a thing in a corner', () {
    final g = Geo(const Rect.fromLTWH(36, 8, 340, 340 / ratio));
    const room = Size(412, 238);
    for (final it in [
      {'kind': 'sticker', 'shape': 'star', 'x': 0.5, 'y': 0.5, 's': 0.12, 'rot': 30.0},
      {'kind': 'dymo', 'text': 'x', 'x': 1.05, 'y': -0.05, 's': 0.05, 'rot': 0.0},
      {'kind': 'washi', 'x': 0.5, 'y': 0.5, 's': 1.2, 'rot': 90.0},
    ]) {
      final h = handlesOf(g, it, room);
      for (final name in ['turn', 'size', 'off']) {
        final p = h[name]!;
        expect(p.dx, inInclusiveRange(14, room.width - 14), reason: '$name of ${it['kind']}');
        expect(p.dy, inInclusiveRange(14, room.height - 14), reason: '$name of ${it['kind']}');
      }
      expect((h['size']! - h['off']!).distance, greaterThanOrEqualTo(39), reason: it['kind'] as String);
    }
  });
}
