/// The small pieces the pages are built from: covers, song rows, the song menu, tape tiles, the tape
/// counter and the bars that dance next to the song that plays.
library;

import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../cassette.dart';
import '../look.dart';
import '../model.dart';

/// Tells the person something, at the bottom of the screen.
void say(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/// A song's cover, decoded at the size it shows (so a list of a hundred songs stays light).
class Cover extends StatelessWidget {
  const Cover(this.track, {super.key, this.size = 48, this.radius = 6});

  final Track track;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final url = track.artAt(px <= 120 ? 120 : (px <= 300 ? 300 : 544));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: url.isEmpty
            ? _blank()
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: px,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _blank(),
                frameBuilder: (_, child, frame, sync) => frame == null && !sync ? _blank() : child,
              ),
      ),
    );
  }

  Widget _blank() => ColoredBox(
        color: Look.raised,
        child: Center(child: Icon(Icons.album_outlined, color: Look.faint, size: size * 0.45)),
      );
}

/// A heading over a part of a page, in the deck's condensed capitals.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 12, 8),
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: Look.cond(13.5, spacing: 2.2))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Builds with the id of the song that plays and whether it plays.
class NowPlayingBuilder extends StatelessWidget {
  const NowPlayingBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, MediaItem? item, bool playing) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: App.audio.mediaItem,
      initialData: App.audio.mediaItem.valueOrNull,
      builder: (context, item) => StreamBuilder<bool>(
        stream: App.audio.playbackState.map((s) => s.playing).distinct(),
        initialData: App.audio.playbackState.valueOrNull?.playing ?? false,
        builder: (context, playing) => builder(context, item.data, playing.data ?? false),
      ),
    );
  }
}

/// One song in a list: cover, title, artist and length, and the menu. The song that plays shows it.
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.track,
    required this.onTap,
    this.current = false,
    this.playing = false,
    this.tape,
    this.index,
    this.number,
  });

  final Track track;
  final VoidCallback onTap;
  final bool current;
  final bool playing;
  final Tape? tape; // the tape the row is on, for "Take off this tape"
  final int? index;
  final int? number; // a place number instead of the cover (on tapes, like a tracklist)

  @override
  Widget build(BuildContext context) {
    final can = track.playable;
    final title = Text(
      track.title.isEmpty ? 'Untitled' : track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Look.ui(15.5, weight: FontWeight.w600, color: current ? Look.accent : (can ? Look.cream : Look.faint)),
    );
    final sub = [
      if (track.artist.isNotEmpty) track.artist,
      if (track.dur > 0) clock(track.dur),
      if (!can) track.src == 'local' ? 'on the computer' : "doesn't play here",
    ].join('  ·  ');
    return InkWell(
      onTap: can ? onTap : () => say(context, "That song is a file on a computer, it doesn't play on the phone."),
      onLongPress: () => songMenu(context, track, tape: tape, index: index),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 4, 7),
        child: Row(children: [
          if (number != null)
            SizedBox(
              width: 30,
              child: current
                  ? PlayingBars(playing: playing, size: 16)
                  : Text('${number!}', textAlign: TextAlign.center, style: Look.cond(15, color: Look.faint)),
            )
          else
            Stack(alignment: Alignment.center, children: [
              Cover(track, size: 48),
              if (current)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Center(child: PlayingBars(playing: playing, size: 18)),
                ),
            ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              title,
              if (sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
                ),
            ]),
          ),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, color: Look.faint),
            onPressed: () => songMenu(context, track, tape: tape, index: index),
          ),
        ]),
      ),
    );
  }
}

/// What can be done with a song: play it next, queue it, like it, put it on a tape, take it off this
/// one, or play songs like it.
Future<void> songMenu(BuildContext context, Track t, {Tape? tape, int? index}) {
  final lib = App.library;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) {
      void done(String? word) {
        Navigator.of(sheet).pop();
        if (word != null) say(context, word);
      }

      final liked = lib.isLiked(t);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Cover(t, size: 44),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5, weight: FontWeight.w600)),
            subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
          ),
          const Divider(height: 1),
          if (t.playable) ...[
            _MenuRow(Icons.playlist_play_rounded, 'Play next', () {
              App.audio.playNext(t);
              done('Plays after this one');
            }),
            _MenuRow(Icons.queue_music_rounded, 'Add to queue', () {
              App.audio.addSongs([t]);
              done('Added to the queue');
            }),
            if (t.src == 'yt')
              _MenuRow(Icons.radio_rounded, 'Songs like this', () {
                App.audio.playSongs([t]);
                done('Playing ${t.title}, and songs like it after');
              }),
          ],
          _MenuRow(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, liked ? 'Unlike' : 'Like', () {
            final now = lib.toggleLike(t);
            done(now ? 'In your liked songs' : 'Out of your liked songs');
          }),
          _MenuRow(Icons.library_add_rounded, 'Put on a tape', () async {
            Navigator.of(sheet).pop();
            await pickTape(context, [t]);
          }),
          if (tape != null && index != null)
            _MenuRow(Icons.remove_circle_outline_rounded, 'Take off this tape', () {
              lib.removeAt(tape, index);
              done('Off ${tape.shownName}');
            }),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text, this.onTap);

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: Look.muted),
        title: Text(text, style: Look.ui(15.5)),
        onTap: onTap,
        dense: true,
        visualDensity: const VisualDensity(vertical: 0.5),
      );
}

/// Which tape the songs go on (or a new one).
Future<void> pickTape(BuildContext context, List<Track> songs) async {
  final lib = App.library;
  final tapes = [
    for (final t in lib.shownTapes)
      if (t.group == null) t,
  ];
  final picked = await showModalBottomSheet<Object>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('PUT ON A TAPE', style: Look.cond(13.5, spacing: 2.2)),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded, color: Look.cream),
            title: Text('New tape', style: Look.ui(15.5, weight: FontWeight.w600)),
            onTap: () => Navigator.of(sheet).pop(true),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: tapes.length,
              itemBuilder: (_, k) {
                final tape = tapes[k];
                return ListTile(
                  leading: SizedBox(width: 56, child: TapeArt(tape: tape, small: true)),
                  title: Text(tape.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5)),
                  subtitle: Text(_count(tape.songs.length), style: Look.ui(13, color: Look.muted)),
                  onTap: () => Navigator.of(sheet).pop(tape),
                );
              },
            ),
          ),
        ]),
      ),
    ),
  );
  if (!context.mounted || picked == null) return;
  Tape? tape = picked is Tape ? picked : null;
  if (picked == true) {
    final name = await askText(context, title: 'New tape', hint: 'Name it', action: 'Make it');
    if (name == null || !context.mounted) return;
    tape = lib.newTape(name);
  }
  if (tape == null) return;
  final n = lib.addTo(tape, songs);
  say(context, n == 0 ? 'Already on ${tape.shownName}' : 'On ${tape.shownName}');
}

String _count(int n) => n == 1 ? '1 song' : '$n songs';

/// Asks for a line of text (a tape's name, say). Null when the person changed their mind.
Future<String?> askText(BuildContext context,
    {required String title, String hint = '', String start = '', String action = 'OK', int max = 80}) {
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _Ask(title: title, hint: hint, start: start, action: action, max: max),
  );
}

class _Ask extends StatefulWidget {
  const _Ask({required this.title, required this.hint, required this.start, required this.action, required this.max});

  final String title, hint, start, action;
  final int max;

  @override
  State<_Ask> createState() => _AskState();
}

class _AskState extends State<_Ask> {
  late final _field = TextEditingController(text: widget.start);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _done() {
    final v = _field.text.trim();
    Navigator.of(context).pop(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Look.side,
      title: Text(widget.title, style: Look.ui(19, weight: FontWeight.w700)),
      content: TextField(
        controller: _field,
        autofocus: true,
        maxLength: widget.max,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint, counterText: ''),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _done, child: Text(widget.action)),
      ],
    );
  }
}

/// A tape as a little cassette with its own label, paper and decorations.
class TapeArt extends StatelessWidget {
  const TapeArt({super.key, required this.tape, this.small = false});

  final Tape tape;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Cassette(
      title: small ? '' : tape.shownName,
      slot: tape.paper ?? slotFor(tape.name),
      design: tape.design,
      layer: App.library.layerOf(tape),
      sticky: small ? '' : tape.note,
      leftNote: small ? '' : tapeFor(tape.seconds),
      rightNote: small ? '' : _count(tape.songs.length),
    );
  }
}

/// A cassette with nothing but a title on its label (the cream paper of the tape stock).
class TapeArtPlain extends StatelessWidget {
  const TapeArtPlain({super.key, required this.title, this.playing = false, this.sticky = '', this.slot = 0});

  final String title;
  final bool playing;
  final String sticky;
  final int slot;

  @override
  Widget build(BuildContext context) => Cassette(title: title, slot: slot, sticky: sticky, playing: playing);
}

/// A tape in a grid or a row: the cassette and its name under it.
class TapeTile extends StatelessWidget {
  const TapeTile({super.key, required this.tape, required this.onTap, this.width = 168});

  final Tape tape;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TapeArt(tape: tape),
            const SizedBox(height: 8),
            Text(tape.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(14.5, weight: FontWeight.w600)),
            Text('${_count(tape.songs.length)}  ·  ${tapeFor(tape.seconds)}',
                maxLines: 1, style: Look.ui(12.5, color: Look.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Little bars that dance next to the song that plays (and stand still while it's paused).
class PlayingBars extends StatefulWidget {
  const PlayingBars({super.key, required this.playing, this.size = 18});

  final bool playing;
  final double size;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _a.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_a.isAnimating) {
      _a.repeat();
    } else if (!widget.playing && _a.isAnimating) {
      _a.stop();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _BarsPainter(_a, Look.accent)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.a, this.color) : super(repaint: a);

  final Animation<double> a;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 4.6;
    final p = Paint()..color = color;
    for (var k = 0; k < 3; k++) {
      final t = a.value * 2 * pi + k * 2.1;
      final h = size.height * (0.3 + 0.7 * (0.5 + 0.5 * sin(t * (k == 1 ? 2 : 1) + k)).abs());
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(k * w * 1.8, size.height - h, w, h), Radius.circular(w / 2)), p);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color;
}

/// The tape counter: digits in lit segments, the way the deck on the computer shows the time.
class Counter extends StatelessWidget {
  const Counter(this.text, {super.key, this.height = 22});

  final String text;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(_Segments.widthOf(text, height), height),
      painter: _Segments(text, Look.accent),
    );
  }
}

class _Segments extends CustomPainter {
  _Segments(this.text, this.on);

  final String text;
  final Color on;

  static double _w(String ch, double h) => ch == ':' ? h * 0.32 : h * 0.62;

  static double widthOf(String text, double h) => text.split('').fold(0.0, (s, ch) => s + _w(ch, h));

  // which of the seven segments each digit lights: top, top right, bottom right, bottom, bottom left,
  // top left, middle
  static const _digits = {
    '0': [1, 1, 1, 1, 1, 1, 0],
    '1': [0, 1, 1, 0, 0, 0, 0],
    '2': [1, 1, 0, 1, 1, 0, 1],
    '3': [1, 1, 1, 1, 0, 0, 1],
    '4': [0, 1, 1, 0, 0, 1, 1],
    '5': [1, 0, 1, 1, 0, 1, 1],
    '6': [1, 0, 1, 1, 1, 1, 1],
    '7': [1, 1, 1, 0, 0, 0, 0],
    '8': [1, 1, 1, 1, 1, 1, 1],
    '9': [1, 1, 1, 1, 0, 1, 1],
    '-': [0, 0, 0, 0, 0, 0, 1],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final lit = Paint()..color = on;
    final ghost = Paint()..color = on.withValues(alpha: 0.1);
    final glow = Paint()
      ..color = on.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    var x = 0.0;
    for (final ch in text.split('')) {
      final cw = _w(ch, h);
      if (ch == ':') {
        final r = h * 0.055;
        for (final y in [h * 0.32, h * 0.7]) {
          canvas.drawCircle(Offset(x + cw / 2, y), r, glow);
          canvas.drawCircle(Offset(x + cw / 2, y), r, lit);
        }
      } else {
        final segs = _digits[ch] ?? const [0, 0, 0, 0, 0, 0, 0];
        final t = h * 0.1; // stroke
        final dw = cw - h * 0.14, left = x + h * 0.07;
        final rects = [
          Rect.fromLTWH(left + t * 0.6, 0, dw - t * 1.2, t),
          Rect.fromLTWH(left + dw - t, t * 0.6, t, h / 2 - t * 0.9),
          Rect.fromLTWH(left + dw - t, h / 2 + t * 0.3, t, h / 2 - t * 0.9),
          Rect.fromLTWH(left + t * 0.6, h - t, dw - t * 1.2, t),
          Rect.fromLTWH(left, h / 2 + t * 0.3, t, h / 2 - t * 0.9),
          Rect.fromLTWH(left, t * 0.6, t, h / 2 - t * 0.9),
          Rect.fromLTWH(left + t * 0.6, h / 2 - t / 2, dw - t * 1.2, t),
        ];
        for (var k = 0; k < 7; k++) {
          final rr = RRect.fromRectAndRadius(rects[k], Radius.circular(t / 2));
          if (segs[k] == 1) {
            canvas.drawRRect(rr, glow);
            canvas.drawRRect(rr, lit);
          } else {
            canvas.drawRRect(rr, ghost);
          }
        }
      }
      x += cw;
    }
  }

  @override
  bool shouldRepaint(_Segments old) => old.text != text || old.on != on;
}
