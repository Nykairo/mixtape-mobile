/// One tape (or the liked songs), the way Spotify shows a playlist but with the cassette on top: its
/// label's color behind it, Play and Shuffle, saving it on the phone, the tape studio, and its songs.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import '../model.dart';
import 'pages.dart';
import 'studio.dart';
import 'widgets.dart';

class TapePage extends StatefulWidget {
  const TapePage({super.key, required Tape this.tape});

  const TapePage.liked({super.key}) : tape = null;

  /// Null for the liked songs.
  final Tape? tape;

  @override
  State<TapePage> createState() => _TapePageState();
}

class _TapePageState extends State<TapePage> {
  late Tape? _tape = widget.tape;

  @override
  void initState() {
    super.initState();
    final t = _tape;
    if (t != null) {
      // after this frame: the library tells its pages, and they can't be told while one is being built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        App.library.openedItem({'kind': 'tape', 'id': t.name, 'title': t.shownName});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([App.library, App.downloads]),
      builder: (context, _) {
        final lib = App.library;
        var tape = _tape;
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
          tape = _tape = now;
        }
        final shown = tape;
        final songs = shown == null ? lib.liked.reversed.toList() : shown.songs;
        final name = shown?.shownName ?? 'Liked songs';
        final from = shown == null ? 'Liked songs' : name;
        final seconds = songs.fold(0, (s, t) => s + t.dur);
        final slot = shown == null ? 3 : (shown.paper ?? slotFor(shown.name));
        final design = shown?.design;
        final shellPaper = design?['paper'] is int ? design!['paper'] as int : slot;
        return Scaffold(
          body: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Color.lerp(Look.bg, paperColor(shellPaper), 0.35),
              surfaceTintColor: Colors.transparent,
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(17, weight: FontWeight.w700)),
              actions: [
                IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert_rounded, color: Look.cream),
                  onPressed: () => shown == null ? _likedMenu(context) : tapeMenu(context, shown),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: ColorTop(
                color: paperColor(shellPaper),
                height: 330,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    NowPlayingBuilder(builder: (context, item, playing) {
                      final here = item != null && App.audio.from == from && songs.any((t) => t.id == item.id);
                      return shown == null
                          ? LikedArt(playing: here && playing)
                          : GestureDetector(
                              onTap: () => StudioPage.open(context, shown),
                              child: TapeArt(tape: shown, playing: here && playing),
                            );
                    }),
                    const SizedBox(height: 16),
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.hand(38, color: Look.cream)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        tapeFor(seconds),
                        count(songs.length),
                        if (seconds > 0) _length(seconds),
                        if (shown?.group != null) 'from the computer',
                      ].join('  ·  '),
                      style: Look.ui(13.5, color: Look.muted),
                    ),
                  ]),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: PlayRow(
                songs: songs,
                from: from,
                name: name,
                extra: [
                  if (shown != null && shown.group == null)
                    IconButton(
                      tooltip: 'Tape studio',
                      onPressed: () => StudioPage.open(context, shown),
                      icon: const Icon(Icons.palette_outlined, color: Look.cream),
                    ),
                ],
              ),
            ),
            if (songs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    shown == null
                        ? "Songs you like show up here. Tap the heart on the player, or Like in a song's menu."
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
                  tape: shown,
                  index: k,
                  onTap: () => App.audio.playSongs(songs, start: k, from: from, tape: shown?.name ?? ''),
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 28)),
          ]),
        );
      },
    );
  }

  static String _length(int seconds) {
    final m = (seconds + 30) ~/ 60;
    return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
  }

  void _likedMenu(BuildContext context) {
    final lib = App.library;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.queue_music_rounded, color: Look.muted),
            title: Text('Add all to the queue', style: Look.ui(15.5)),
            onTap: () {
              Navigator.of(sheet).pop();
              App.audio.addSongs(lib.liked.reversed.toList());
              say(context, 'Added to the queue');
            },
          ),
          ListTile(
            leading: const Icon(Icons.library_add_outlined, color: Look.muted),
            title: Text('Save as a tape', style: Look.ui(15.5)),
            onTap: () async {
              Navigator.of(sheet).pop();
              final title = await askText(context, title: 'Save as a tape', start: 'Liked songs', action: 'Save');
              if (title == null || !context.mounted) return;
              final tape = lib.newTape(title, songs: lib.liked.reversed.toList());
              say(context, 'Saved as ${tape.shownName}');
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

/// Everything that can be done with a tape (from its page, or a long press in the library).
Future<void> tapeMenu(BuildContext context, Tape tape) {
  final lib = App.library;
  final d = App.downloads;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) {
      final pinned = lib.isPinned(tape.name);
      final (have, total) = d.count(tape.songs);
      final saving = d.busyWith(tape.songs);
      void go(Future<void> Function() then) {
        Navigator.of(sheet).pop();
        then();
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: SizedBox(width: 64, child: TapeArt(tape: tape, small: true)),
              title: Text(tape.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(16, weight: FontWeight.w700)),
              subtitle: Text(count(tape.songs.length), style: Look.ui(13, color: Look.muted)),
            ),
            const Divider(height: 1),
            _row(Icons.push_pin_outlined, pinned ? 'Unpin' : 'Pin to the top', () => go(() async => lib.pin(tape.name, !pinned))),
            if (total > 0)
              _row(
                  saving
                      ? Icons.stop_circle_outlined
                      : (have == total ? Icons.delete_outline_rounded : Icons.arrow_circle_down_outlined),
                  saving ? 'Stop saving it' : (have == total ? 'Take it off the phone' : 'Save it on the phone'),
                  () => go(() async {
                        if (saving) {
                          d.cancel(tape.songs);
                        } else if (have == total) {
                          await d.remove(tape.songs);
                        } else {
                          d.save(tape.songs, name: tape.shownName);
                        }
                      })),
            if (tape.group == null) _row(Icons.palette_outlined, 'Decorate it', () => go(() => StudioPage.open(context, tape))),
            _row(Icons.edit_outlined, 'Rename', () => go(() async {
                  final name = await askText(context, title: 'Rename tape', start: tape.name, action: 'Rename');
                  if (name != null) lib.rename(tape, name);
                })),
            _row(Icons.sticky_note_2_outlined, 'Write on the sticky note', () => go(() async {
                  final text = await askText(context,
                      title: 'Sticky note',
                      hint: 'A few words for the corner (none takes it off)',
                      start: tape.note,
                      action: 'Stick it on',
                      max: 28,
                      blank: true);
                  if (text != null) lib.setNote(tape, text);
                })),
            if (tape.songs.length > 1)
              _row(Icons.swap_vert_rounded, 'Change the order', () => go(() => EditOrder.open(context, tape))),
            _row(Icons.queue_music_rounded, 'Add all to the queue', () => go(() async {
                  await App.audio.addSongs(tape.songs);
                  if (context.mounted) say(context, 'Added to the queue');
                })),
            _row(Icons.delete_forever_outlined, 'Delete tape', () => go(() async {
                  final sure = await showDialog<bool>(
                    context: context,
                    useRootNavigator: true,
                    builder: (dlg) => AlertDialog(
                      backgroundColor: Look.side,
                      title: Text('Delete ${tape.shownName}?', style: Look.ui(19, weight: FontWeight.w700)),
                      content: Text(
                        App.account.signedIn
                            ? 'It goes from this phone and from your Mixtape Account, so from the computer too.'
                            : 'It goes from this phone.',
                        style: Look.ui(15, color: Look.muted, height: 1.4),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(dlg).pop(false), child: const Text('Keep it')),
                        FilledButton(onPressed: () => Navigator.of(dlg).pop(true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (sure == true) lib.deleteTape(tape);
                })),
            const SizedBox(height: 8),
          ]),
        ),
      );
    },
  );
}

Widget _row(IconData icon, String text, VoidCallback onTap) => ListTile(
      leading: Icon(icon, color: Look.muted),
      title: Text(text, style: Look.ui(15.5)),
      onTap: onTap,
      dense: true,
      visualDensity: const VisualDensity(vertical: 0.5),
    );

/// Dragging a tape's songs into another order.
class EditOrder extends StatefulWidget {
  const EditOrder({super.key, required this.tape});

  final Tape tape;

  static Future<void> open(BuildContext context, Tape tape) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => EditOrder(tape: tape)));

  @override
  State<EditOrder> createState() => _EditOrderState();
}

class _EditOrderState extends State<EditOrder> {
  @override
  Widget build(BuildContext context) {
    final songs = widget.tape.songs;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Look.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Change the order', style: Look.ui(18, weight: FontWeight.w700)),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
      ),
      body: ReorderableListView.builder(
        itemCount: songs.length,
        onReorderItem: (from, to) => setState(() => App.library.move(widget.tape, from, to)),
        itemBuilder: (context, k) => ListTile(
          key: ValueKey('${songs[k].id}-$k'),
          leading: Cover(songs[k], size: 42),
          title: Text(songs[k].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15)),
          subtitle: Text(songs[k].artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(12.5, color: Look.muted)),
          trailing: const Icon(Icons.drag_handle_rounded, color: Look.faint),
        ),
      ),
    );
  }
}
