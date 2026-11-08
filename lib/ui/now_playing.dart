/// The big player: the cassette that plays (the tape's own when it comes from a tape) with its reels
/// turning, or the cover, a tap away from each other; the song, the counter, the keys and the queue.
library;

import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../cassette.dart';
import '../look.dart';
import '../model.dart';
import 'shell.dart';
import 'widgets.dart';

class NowPlaying extends StatefulWidget {
  const NowPlaying({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => const NowPlaying(),
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
          child: child,
        ),
      ));

  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> {
  bool _cover = false; // the cover instead of the cassette
  double? _dragging; // where the seek slider is held, in seconds
  double _pull = 0; // how far the page is pulled down to close it

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: App.audio.mediaItem,
      initialData: App.audio.mediaItem.valueOrNull,
      builder: (context, snap) {
        final t = App.audio.current;
        if (snap.data == null || t == null) {
          return Scaffold(
            body: Center(
              child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Nothing plays. Close')),
            ),
          );
        }
        return GestureDetector(
          onVerticalDragUpdate: (d) => setState(() => _pull = max(0, _pull + d.delta.dy)),
          onVerticalDragEnd: (d) {
            if (_pull > 120 || (d.primaryVelocity ?? 0) > 700) {
              Navigator.of(context).pop();
            } else {
              setState(() => _pull = 0);
            }
          },
          child: Transform.translate(
            offset: Offset(0, _pull),
            child: Scaffold(
              body: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.55),
                    radius: 1.1,
                    colors: [Look.accent.withValues(alpha: 0.16), Look.bg],
                  ),
                ),
                child: SafeArea(child: _page(context, t)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _page(BuildContext context, Track t) {
    final audio = App.audio;
    final from = audio.from;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Look.cream),
          ),
          Expanded(
            child: Column(children: [
              Text(from.isEmpty ? 'NOW PLAYING' : 'PLAYING FROM', style: Look.cond(11.5, spacing: 2.2)),
              if (from.isNotEmpty)
                Text(from, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13.5, weight: FontWeight.w600)),
            ]),
          ),
          IconButton(
            tooltip: 'Queue',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QueuePage())),
            icon: const Icon(Icons.queue_music_rounded, color: Look.cream),
          ),
        ]),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _cover = !_cover),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOut,
            child: _cover ? _BigCover(key: const ValueKey('cover'), track: t) : _Deck(key: const ValueKey('deck'), track: t),
          ),
        ),
        const SizedBox(height: 6),
        Text(_cover ? 'Tap for the tape' : 'Tap for the cover', style: Look.ui(11.5, color: Look.faint)),
        const Spacer(),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(23, weight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 4),
              Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5, color: Look.muted)),
            ]),
          ),
          ListenableBuilder(
            listenable: App.library,
            builder: (context, _) {
              final liked = App.library.isLiked(t);
              return IconButton(
                tooltip: liked ? 'Unlike' : 'Like',
                iconSize: 28,
                onPressed: () => App.library.toggleLike(t),
                icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: liked ? Look.accent : Look.cream),
              );
            },
          ),
        ]),
        const SizedBox(height: 10),
        _Seek(track: t, dragging: _dragging, onDrag: (v) => setState(() => _dragging = v)),
        const SizedBox(height: 6),
        const _Keys(),
        const SizedBox(height: 10),
        Row(children: [
          TextButton.icon(
            onPressed: () => pickTape(context, [t]),
            icon: const Icon(Icons.library_add_rounded, size: 20),
            label: const Text('Put on a tape'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => songMenu(context, t),
            icon: const Icon(Icons.more_horiz_rounded, size: 20),
            label: const Text('More'),
          ),
        ]),
        const SizedBox(height: 6),
      ]),
    );
  }
}

/// The cassette that plays: its label says the song, the cover is glued on, the reels go round.
class _Deck extends StatelessWidget {
  const _Deck({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final audio = App.audio;
    final tape = App.library.tapes[audio.fromTape];
    final liked = audio.from == 'Liked songs';
    return StreamBuilder<Duration>(
      stream: audio.position,
      builder: (context, pos) {
        final total = audio.player.duration ?? Duration(seconds: track.dur);
        final ms = total.inMilliseconds;
        final f = ms <= 0 ? 0.0 : ((pos.data ?? Duration.zero).inMilliseconds / ms).clamp(0.0, 1.0);
        return NowPlayingBuilder(
          builder: (context, item, playing) => Cassette(
            title: track.title,
            slot: tape?.paper ?? (tape != null ? slotFor(tape.name) : (liked ? 3 : 0)),
            design: tape?.design,
            sticky: tape?.note ?? (liked ? "don't tape over!" : ''),
            progress: (f * 200).round() / 200, // the packs move in steps too small to see
            playing: playing,
            cover: track.artAt(300),
          ),
        );
      },
    );
  }
}

class _BigCover extends StatelessWidget {
  const _BigCover({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final side = min(box.maxWidth, MediaQuery.sizeOf(context).height * 0.42);
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, 12))],
        ),
        child: Cover(track, size: side, radius: 14),
      );
    });
  }
}

/// Where the song is: the counter, the slider, and how long it has left.
class _Seek extends StatelessWidget {
  const _Seek({required this.track, required this.dragging, required this.onDrag});

  final Track track;
  final double? dragging;
  final ValueChanged<double?> onDrag;

  @override
  Widget build(BuildContext context) {
    final audio = App.audio;
    return StreamBuilder<Duration>(
      stream: audio.position,
      builder: (context, snap) {
        final total = (audio.player.duration ?? Duration(seconds: track.dur)).inMilliseconds / 1000;
        final now = (snap.data ?? Duration.zero).inMilliseconds / 1000;
        final double shown = min(max(dragging ?? now, 0.0), max(total, 0.0));
        final left = max(0, (total - shown).round());
        return Column(children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(overlayShape: const RoundSliderOverlayShape(overlayRadius: 16)),
            child: Slider(
              value: total <= 0 ? 0.0 : shown,
              max: total <= 0 ? 1.0 : total,
              onChanged: total <= 0 ? null : onDrag,
              onChangeEnd: (v) {
                audio.seek(Duration(milliseconds: (v * 1000).round()));
                onDrag(null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              Counter(clock(shown.round()), height: 18),
              const Spacer(),
              Text(total <= 0 ? '' : '-${clock(left)}', style: Look.cond(14, color: Look.muted, spacing: 0.8)),
            ]),
          ),
        ]);
      },
    );
  }
}

/// Shuffle, back, play or pause, next, and repeat.
class _Keys extends StatelessWidget {
  const _Keys();

  @override
  Widget build(BuildContext context) {
    final audio = App.audio;
    return StreamBuilder<PlaybackState>(
      stream: audio.playbackState,
      initialData: audio.playbackState.valueOrNull,
      builder: (context, snap) {
        final s = snap.data;
        final shuffle = s?.shuffleMode == AudioServiceShuffleMode.all;
        final repeat = s?.repeatMode ?? AudioServiceRepeatMode.none;
        return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(
            tooltip: shuffle ? 'Shuffle is on' : 'Shuffle',
            onPressed: () => audio.setShuffleMode(shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all),
            icon: Icon(Icons.shuffle_rounded, color: shuffle ? Look.accent : Look.muted),
          ),
          IconButton(
            tooltip: 'Back',
            iconSize: 40,
            onPressed: audio.skipToPrevious,
            icon: const Icon(Icons.skip_previous_rounded, color: Look.cream),
          ),
          const PlayButton(size: 74),
          IconButton(
            tooltip: 'Next',
            iconSize: 40,
            onPressed: audio.skipToNext,
            icon: const Icon(Icons.skip_next_rounded, color: Look.cream),
          ),
          IconButton(
            tooltip: switch (repeat) {
              AudioServiceRepeatMode.one => 'Repeats this song',
              AudioServiceRepeatMode.none => 'Repeat',
              _ => 'Repeats the queue',
            },
            onPressed: () => audio.setRepeatMode(switch (repeat) {
              AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
              AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
              _ => AudioServiceRepeatMode.none,
            }),
            icon: Icon(repeat == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                color: repeat == AudioServiceRepeatMode.none ? Look.muted : Look.accent),
          ),
        ]);
      },
    );
  }
}

/// What plays after this: tap a song to jump to it, swipe one away to take it out.
class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = App.audio;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Look.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Queue', style: Look.ui(19, weight: FontWeight.w700)),
      ),
      body: StreamBuilder(
        stream: audio.views,
        builder: (context, _) {
          final view = audio.view;
          if (view.songs.isEmpty) {
            return Center(child: Text('Nothing in the queue.', style: Look.ui(15, color: Look.muted)));
          }
          final after = view.songs.length - view.index - 1;
          return NowPlayingBuilder(
            builder: (context, item, playing) => ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: 3 + max(0, after),
              itemBuilder: (context, k) {
                if (k == 0) return const SectionTitle('Now playing');
                if (k == 2) {
                  return SectionTitle(after <= 0
                      ? (audio.autoplay ? 'Next: songs like this one' : 'That was the last one')
                      : 'Next up  ·  $after');
                }
                final i = k == 1 ? view.index : view.index + (k - 2);
                if (i < 0 || i >= view.songs.length) return const SizedBox.shrink();
                final t = view.songs[i];
                final row = SongRow(
                  track: t,
                  current: i == view.index,
                  playing: playing,
                  onTap: () => audio.playShown(i),
                );
                if (i <= view.index) return row;
                return Dismissible(
                  key: ValueKey('${t.id}-$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Look.raised,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.remove_circle_outline_rounded, color: Look.muted),
                  ),
                  onDismissed: (_) => audio.removeShown(i),
                  child: row,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
