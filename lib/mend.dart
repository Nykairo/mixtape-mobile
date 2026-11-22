/// Songs that lost their artist get it back. Before 0.3.3 a count of plays in the phone's own language
/// ("1,2 Mio. Aufrufe") could end up where the artist belongs; such counts are dropped as the songs load
/// (model.dart), and here YouTube Music is asked who each of those songs is by, one after the other, a
/// little while after the app opened. The plays, the liked songs and the tapes get the name written back.
library;

import 'dart:async';

import 'app.dart';
import 'innertube.dart';
import 'model.dart';
import 'music.dart';
import 'store.dart';
import 'youtube.dart';

const _file = 'mended.json';

class Mend {
  Mend._();

  static Timer? _timer;

  /// Starts once, twenty seconds after the app opened, so it never slows the start.
  static void soon() => _timer ??= Timer(const Duration(seconds: 20), () => artists().ignore());

  /// Asks about up to [most] songs without an artist, the latest plays first. A song is asked about
  /// once ever (also when YouTube has no answer for it), and a lost connection ends the round: the
  /// rest wait for the next start. Gives how many songs got their artist back.
  static Future<int> artists({int most = 40, Duration gap = const Duration(milliseconds: 400)}) async {
    final asked = {...await _asked()};
    final want = <String>[];
    void look(Track t) {
      if (want.length < most && t.src == 'yt' && t.artist.isEmpty && !asked.contains(t.ref) && !want.contains(t.ref)) {
        want.add(t.ref);
      }
    }

    for (final p in App.history.plays.reversed) {
      look(p.track);
    }
    for (final t in [...App.library.liked.reversed, ...App.library.recent]) {
      look(t);
    }
    for (final tape in App.library.tapes.values) {
      tape.songs.forEach(look);
    }
    if (want.isEmpty) return 0;
    final found = <String, Track>{};
    for (final ref in want) {
      try {
        final next = parseNext(await YouTube.inner.nextRaw(ref), ref);
        for (final t in next.songs) {
          if (t.ref == ref && t.artist.isNotEmpty) found['yt$ref'] = t;
        }
        asked.add(ref);
      } on InnerTubeError catch (e) {
        if (e.why == 'network' || e.why == 'busy') break; // offline, or YouTube wants a pause: next time
        asked.add(ref); // the song itself is the trouble (gone, private): no use asking again
      }
      await Future<void>.delayed(gap);
    }
    final keep = asked.toList();
    await Store.the.write(_file, keep.length > 4000 ? keep.sublist(keep.length - 4000) : keep);
    if (found.isNotEmpty) {
      App.history.giveArtists(found);
      App.library.giveArtists(found);
    }
    return found.length;
  }

  static Future<List<String>> _asked() async {
    final j = await Store.the.read(_file);
    return [
      if (j is List)
        for (final x in j) '$x',
    ];
  }
}
