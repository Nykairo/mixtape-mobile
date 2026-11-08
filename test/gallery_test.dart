// Pictures of the cassettes and a few pieces of the pages, drawn with the real fonts, to look at:
// `flutter test --tags gallery --update-goldens` writes them to test/goldens/ (the build on GitHub puts
// them on the "screens" branch). Not a check, so it doesn't run with the other tests.
@Tags(['gallery'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/cassette.dart';
import 'package:mixtape/look.dart';
import 'package:mixtape/model.dart';
import 'package:mixtape/ui/widgets.dart';

Future<void> _fonts() async {
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

Widget _frame(Widget child, {double width = 412}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Look.theme(),
      home: Scaffold(
        body: Center(child: SizedBox(width: width, child: child)),
      ),
    );

void main() {
  setUpAll(_fonts);

  testWidgets('cassettes', (tester) async {
    tester.view.physicalSize = const Size(1000, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final looks = <(String, int, Map<String, Object?>?, String)>[
      ('Road trip', 0, null, 'windows down'),
      ('Sunday morning', 1, null, ''),
      ('Rain', 2, {'shell': 'smoke', 'hub': 'mint', 'stripes': 'lines'}, ''),
      ('Liked songs', 3, null, "don't tape over!"),
      ('Night drive', 7, {'shell': 'clear', 'finish': 'glitter', 'tape': 'chrome', 'pen': 'marker'}, ''),
      ('for you', 5, {'shell': 'white', 'finish': 'gloss', 'stripes': 'fade', 'screws': 'gold', 'pen': 'print'}, 'xoxo'),
      ('Gym', 4, {'shell': 'red', 'hub': 'black', 'stripes': 'band', 'pen': 'type'}, ''),
      ('Summer 26', 9, {'shell': 'mint', 'corner_color': 'pink', 'ink': 'purple'}, 'beach!!'),
    ];
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Look.theme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 2,
            childAspectRatio: ratio,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              for (final (title, slot, design, note) in looks)
                Cassette(
                  title: title,
                  slot: slot,
                  design: design,
                  sticky: note,
                  leftNote: 'C60',
                  rightNote: '14 songs',
                  progress: 0.3,
                ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/cassettes.png'));
  });

  testWidgets('song rows and the counter', (tester) async {
    tester.view.physicalSize = const Size(412, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final songs = [
      const Track(src: 'yt', ref: 'a', title: 'Get Lucky (feat. Pharrell Williams)', artist: 'Daft Punk', dur: 369),
      const Track(src: 'yt', ref: 'b', title: 'Holocene', artist: 'Bon Iver', dur: 337),
      const Track(src: 'local', ref: '/music/demo.flac', title: 'Demo take 3', artist: 'Me', dur: 201),
    ];
    await tester.pumpWidget(_frame(
      Column(mainAxisSize: MainAxisSize.min, children: [
        const SectionTitle('Played lately'),
        SongRow(track: songs[0], onTap: () {}, current: true, playing: false),
        SongRow(track: songs[1], onTap: () {}, number: 2),
        SongRow(track: songs[2], onTap: () {}),
        const SizedBox(height: 20),
        const Counter('3:27', height: 30),
      ]),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/rows.png'));
  });
}
