/// One tape (or the liked songs): the cassette as it was decorated, Play and Shuffle, and its songs.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../cassette.dart';
import '../look.dart';
import '../model.dart';
import 'widgets.dart';

class TapePage extends StatelessWidget {
  const TapePage._({this.tape});

  /// Null for the liked songs.
  final Tape? tape;

  static Route<void> of(Tape tape) => MaterialPageRoute<void>(builder: (_) => TapePage._(tape: tape));

  static Route<void> liked() => MaterialPageRoute<void>(builder: (_) => const TapePage._());

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.library,
      builder: (context, _) {
        final lib = App.library;
        final tape = this.tape;
        // the tape changed on the computer meanwhile, was renamed here, or was deleted: this page follows
        if (tape != null && !identical(lib.tapes[tape.name], tape)) {
          var now = lib.tapes[tape.name];
          for (final t in lib.tapes.values) {
            if (now == null && identical(t.songs, tape.songs)) now = t; // renamed (it keeps its songs)
          }
          if (now == null) {
            return Scaffold(
              appBar: AppBar(backgroundColor: Look.bg),
              body: Center(child: Text('This tape is gone.', style: Look.ui(16, color: Look.muted))),
            );
          }
          return TapePage._(tape: now);
        }
        final songs = tape == null ? lib.liked.reversed.toList() : tape.songs;
        final name = tape?.shownName ?? 'Liked songs';
        final from = tape == null ? 'Liked songs' : name;
        final playable = songs.where((t) => t.playable).length;
        final seconds = songs.fold(0, (s, t) => s + t.dur);
        return Scaffold(
          body: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Look.bg,
              surfaceTintColor: Colors.transparent,
              title: Text(name, style: Look.ui(18, weight: FontWeight.w700)),
              actions: [
                if (tape != null)
                  PopupMenuButton<String>(
                    color: Look.raised,
                    icon: const Icon(Icons.more_vert_rounded, color: Look.cream),
                    onSelected: (what) => _menu(context, tape, what),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      const PopupMenuItem(value: 'note', child: Text('Write on the sticky note')),
                      const PopupMenuItem(value: 'queue', child: Text('Add all to the queue')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete tape')),
                    ],
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                child: NowPlayingBuilder(
                  builder: (context, item, playing) {
                    final here = item != null && songs.any((t) => t.id == item.id) && App.audio.from == from;
                    return Cassette(
                      title: name,
                      slot: tape == null ? 3 : (tape.paper ?? slotFor(tape.name)),
                      design: tape?.design,
                      layer: tape == null ? null : lib.layerOf(tape),
                      sticky: tape == null ? "don't tape over!" : tape.note,
                      leftNote: tapeFor(seconds),
                      rightNote: '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                      playing: here && playing,
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(22, weight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(
                        [
                          tapeFor(seconds),
                          '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                          if (seconds > 0) _length(seconds),
                        ].join('  ·  '),
                        style: Look.ui(13.5, color: Look.muted),
                      ),
                    ]),
                  ),
                  IconButton.outlined(
                    tooltip: 'Shuffle',
                    onPressed: playable == 0 ? null : () => App.audio.playSongs(songs, shuffle: true, from: from, tape: tape?.name ?? ''),
                    icon: const Icon(Icons.shuffle_rounded),
                    style: IconButton.styleFrom(side: const BorderSide(color: Look.edge), foregroundColor: Look.cream),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Play',
                    iconSize: 30,
                    onPressed: playable == 0 ? null : () => App.audio.playSongs(songs, from: from, tape: tape?.name ?? ''),
                    icon: const Icon(Icons.play_arrow_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Look.accent,
                      foregroundColor: Look.bg,
                      minimumSize: const Size(54, 54),
                    ),
                  ),
                ]),
              ),
            ),
            if (songs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    tape == null
                        ? 'Songs you like show up here. Tap the heart on the player, or Like in a song\'s menu.'
                        : 'Nothing on this tape yet. Find songs in Search and put them on it from their menu.',
                    style: Look.ui(15, color: Look.muted, height: 1.4),
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, k) => NowPlayingBuilder(
                builder: (context, item, playing) => SongRow(
                  track: songs[k],
                  number: k + 1,
                  current: item?.id == songs[k].id,
                  playing: playing,
                  tape: tape,
                  index: k,
                  onTap: () => App.audio.playSongs(songs, start: k, from: from, tape: tape?.name ?? ''),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ]),
        );
      },
    );
  }

  static String _length(int seconds) {
    final m = (seconds + 30) ~/ 60;
    return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
  }

  Future<void> _menu(BuildContext context, Tape tape, String what) async {
    final lib = App.library;
    switch (what) {
      case 'rename':
        final name = await askText(context, title: 'Rename tape', start: tape.name, action: 'Rename');
        if (name == null || !context.mounted) return;
        lib.rename(tape, name); // the page follows the tape to its new name
      case 'note':
        final text = await askText(context,
            title: 'Sticky note', hint: 'A few words for the corner', start: tape.note, action: 'Stick it on', max: 28);
        if (!context.mounted) return;
        lib.setNote(tape, text ?? '');
      case 'queue':
        await App.audio.addSongs(tape.songs);
        if (context.mounted) say(context, 'Added to the queue');
      case 'delete':
        final sure = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            backgroundColor: Look.side,
            title: Text('Delete ${tape.shownName}?', style: Look.ui(19, weight: FontWeight.w700)),
            content: Text(
              App.account.signedIn
                  ? 'It goes from this phone and from your Mixtape Account, so from the computer too.'
                  : 'It goes from this phone.',
              style: Look.ui(15, color: Look.muted, height: 1.4),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Keep it')),
              FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Delete')),
            ],
          ),
        );
        if (sure != true || !context.mounted) return;
        lib.deleteTape(tape);
        Navigator.of(context).pop();
    }
  }
}
