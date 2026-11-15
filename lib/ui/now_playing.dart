/// The big player, in the color of the song's cover (like Spotify), with YouTube Music's switch on top:
/// the cover, the cassette (the tape's own when it comes from a tape, reels turning), or the music
/// video. The song, its chips (save, tape, share, sleep, speed), the counter and the keys, and at the
/// bottom Up next, Lyrics and Related.
library;

import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../cassette.dart';
import '../look.dart';
import '../model.dart';
import '../music.dart';
import '../rooms.dart' as rooms;
import 'lyrics_view.dart';
import 'pages.dart';
import 'shell.dart';
import 'tint.dart';
import 'video_view.dart';
import 'widgets.dart';

class NowPlaying extends StatefulWidget {
  const NowPlaying({super.key});

  /// What the top shows: 'cover', 'tape' or 'video' (kept for the next time the player opens).
  static String view = 'cover';

  static Future<void> open(BuildContext context) => Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 340),
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
  double? _dragging; // where the seek slider is held, in seconds
  double _pull = 0; // how far the page is pulled down to close it

  void _setView(String v) => setState(() => NowPlaying.view = v);

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
            child: TintBuilder(
              builder: (context, tint) => Scaffold(
                backgroundColor: Look.bg,
                body: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [shade(tint, 0.46), shade(tint, 0.22), Look.bg],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                  child: SafeArea(child: _page(context, t)),
                ),
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
    return LayoutBuilder(builder: (context, box) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(children: [
          Row(children: [
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Look.cream),
            ),
            Expanded(child: Center(child: _Switch(view: NowPlaying.view, onPick: _setView))),
            IconButton(
              tooltip: 'More',
              onPressed: () => songMenu(context, t),
              icon: const Icon(Icons.more_vert_rounded, color: Look.cream),
            ),
          ]),
          if (from.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('PLAYING FROM  ${from.toUpperCase()}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.cond(11.5, spacing: 1.8, color: Look.cream.withValues(alpha: 0.7))),
            ),
          // the cover, the cassette or the video gets the room that's left: big on a big phone, and
          // on a small one (or with big letters) it gives way instead of pushing the keys off the screen
          Expanded(
            child: LayoutBuilder(builder: (context, room) {
              final wide = box.maxWidth - 44;
              final high = max(0.0, room.maxHeight - 24);
              final tape = NowPlaying.view == 'tape';
              final art = tape ? min(wide, high * ratio) : min(wide, high);
              return Center(
                child: SizedBox(
                  width: art,
                  height: tape ? art / ratio : art,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: child),
                    ),
                    child: switch (NowPlaying.view) {
                      'tape' => SizedBox(key: const ValueKey('tape'), width: art, child: _Deck(track: t)),
                      'video' => VideoView(key: const ValueKey('video'), track: t, size: art),
                      _ => _BigCover(key: ValueKey('cover${t.id}'), track: t, size: art),
                    },
                  ),
                ),
              );
            }),
          ),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(23, weight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 2),
                InkWell(
                  onTap: () {
                    final id = '${t.extra['artist_id'] ?? ''}';
                    final name = t.artist.split(',').first;
                    Shell.push(id.isNotEmpty ? ArtistView(id: id, name: name) : SearchResultsView(query: name, filter: 'artists'));
                  },
                  child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Look.ui(16, color: Look.cream.withValues(alpha: 0.72))),
                ),
              ]),
            ),
            ListenableBuilder(
              listenable: App.library,
              builder: (context, _) {
                final liked = App.library.isLiked(t);
                return IconButton(
                  tooltip: liked ? 'Unlike' : 'Like',
                  iconSize: 30,
                  onPressed: () => App.library.toggleLike(t),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        key: ValueKey(liked), color: liked ? Look.accent : Look.cream),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 10),
          _Chips(track: t),
          const SizedBox(height: 6),
          _Seek(track: t, dragging: _dragging, onDrag: (v) => setState(() => _dragging = v)),
          const _Keys(),
          const SizedBox(height: 4),
          _Tabs(track: t),
        ]),
      );
    });
  }
}

/// Song, tape or video: YouTube Music's switch, with the cassette in the middle.
class _Switch extends StatelessWidget {
  const _Switch({required this.view, required this.onPick});

  final String view;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(22)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (key, name) in const [('cover', 'Song'), ('tape', 'Tape'), ('video', 'Video')])
          GestureDetector(
            onTap: () => onPick(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: view == key ? Look.cream.withValues(alpha: 0.92) : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(name, style: Look.ui(13, weight: FontWeight.w700, color: view == key ? Look.bg : Look.cream)),
            ),
          ),
      ]),
    );
  }
}

/// The cassette that plays: its label says the song, the cover is glued on, the reels go round.
class _Deck extends StatelessWidget {
  const _Deck({required this.track});

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
            layer: tape == null ? null : App.library.layerOf(tape),
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
  const _BigCover({super.key, required this.track, required this.size});

  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 34, offset: Offset(0, 16))],
        ),
        child: Cover(track, size: size, radius: 12),
      ),
    );
  }
}

/// The chips under the song: save it, put it on a tape, share it, the sleep timer and the speed.
class _Chips extends StatelessWidget {
  const _Chips({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        ListenableBuilder(
          listenable: App.downloads,
          builder: (context, _) {
            final d = App.downloads;
            final saved = d.has(track);
            final busy = d.isWaiting(track);
            return Pill(
              saved ? Icons.arrow_circle_down_rounded : (busy ? Icons.downloading_rounded : Icons.arrow_circle_down_outlined),
              saved ? 'On the phone' : (busy ? 'Saving…' : 'Save'),
              track.src != 'yt' || busy
                  ? null
                  : () {
                      if (saved) {
                        d.remove([track]);
                      } else {
                        d.save([track]);
                      }
                    },
              on: saved,
            );
          },
        ),
        const SizedBox(width: 8),
        Pill(Icons.library_add_outlined, 'Tape', () => pickTape(context, [track])),
        const SizedBox(width: 8),
        Pill(Icons.ios_share_rounded, 'Share', () => shareSong(context, track)),
        const SizedBox(width: 8),
        const _SleepPill(),
        const SizedBox(width: 8),
        StreamBuilder<PlaybackState>(
          stream: App.audio.playbackState,
          initialData: App.audio.playbackState.valueOrNull,
          builder: (context, s) {
            final speed = s.data?.speed ?? 1.0;
            return Pill(Icons.speed_rounded, '${_speed(speed)}×', () => _speedSheet(context, speed), on: speed != 1.0);
          },
        ),
      ]),
    );
  }

  static String _speed(double s) => s == s.roundToDouble() ? s.toStringAsFixed(0) : '$s';

  static void _speedSheet(BuildContext context, double now) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('SPEED', style: Look.cond(13.5, spacing: 2.2)),
          ),
          for (final s in const [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0])
            ListTile(
              title: Text('${_speed(s)}×${s == 1.0 ? '  (as recorded)' : ''}', style: Look.ui(15.5, weight: FontWeight.w600)),
              trailing: (s - now).abs() < 0.001 ? Icon(Icons.check_rounded, color: Look.accent) : null,
              onTap: () {
                App.audio.setSpeed(s);
                Navigator.of(sheet).pop();
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

/// The sleep timer: after some minutes, or at the end of the song that plays.
class _SleepPill extends StatefulWidget {
  const _SleepPill();

  @override
  State<_SleepPill> createState() => _SleepPillState();
}

class _SleepPillState extends State<_SleepPill> {
  Timer? _tick;
  StreamSubscription<void>? _news;

  @override
  void initState() {
    super.initState();
    _news = App.audio.sleepNews.stream.listen((_) => _changed());
    _changed();
  }

  void _changed() {
    _tick?.cancel();
    if (App.audio.sleepAt != null) _tick = Timer.periodic(const Duration(seconds: 15), (_) => setState(() {}));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    _news?.cancel();
    super.dispose();
  }

  void _sheet() {
    final audio = App.audio;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheet) {
        void pick(VoidCallback what, String word) {
          what();
          Navigator.of(sheet).pop();
          say(context, word);
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('SLEEP TIMER', style: Look.cond(13.5, spacing: 2.2)),
              ),
              for (final m in const [5, 10, 15, 30, 45, 60, 90])
                ListTile(
                  dense: true,
                  title: Text(m < 60 ? '$m minutes' : (m == 60 ? '1 hour' : '1 hour 30'), style: Look.ui(15.5)),
                  onTap: () => pick(() => audio.sleepIn(Duration(minutes: m)), 'The music fades out in $m minutes'),
                ),
              ListTile(
                dense: true,
                title: Text('At the end of this song', style: Look.ui(15.5)),
                onTap: () => pick(audio.sleepAfterSong, 'The music stops after this song'),
              ),
              if (audio.sleepAt != null || audio.sleepAtEnd)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.close_rounded, color: Look.muted),
                  title: Text('Turn it off', style: Look.ui(15.5)),
                  onTap: () => pick(audio.sleepOff, 'Sleep timer is off'),
                ),
              const SizedBox(height: 8),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = App.audio;
    final at = audio.sleepAt;
    final left = at == null ? 0 : max(1, (at.difference(DateTime.now()).inSeconds / 60).ceil());
    final text = at != null ? '$left min' : (audio.sleepAtEnd ? 'End of song' : 'Sleep');
    return Pill(Icons.bedtime_outlined, text, _sheet, on: at != null || audio.sleepAtEnd);
  }
}

/// Where the song is: the tape counter, the slider, and how long it has left.
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
            data: SliderTheme.of(context).copyWith(
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Look.cream,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
              thumbColor: Look.cream,
            ),
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
              Counter(clock(shown.round()), height: 17, color: Look.cream),
              const Spacer(),
              Text(total <= 0 ? '' : '-${clock(left)}', style: Look.cond(14, color: Look.cream.withValues(alpha: 0.7), spacing: 0.8)),
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
            icon: Icon(Icons.shuffle_rounded, color: shuffle ? Look.accent : Look.cream.withValues(alpha: 0.75)),
          ),
          IconButton(
            tooltip: 'Back',
            iconSize: 42,
            onPressed: audio.skipToPrevious,
            icon: const Icon(Icons.skip_previous_rounded, color: Look.cream),
          ),
          const PlayButton(size: 72),
          IconButton(
            tooltip: 'Next',
            iconSize: 42,
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
                color: repeat == AudioServiceRepeatMode.none ? Look.cream.withValues(alpha: 0.75) : Look.accent),
          ),
        ]);
      },
    );
  }
}

/// YouTube Music's three tabs at the bottom of the player: each opens the sheet on its page.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (final (k, name) in const [(0, 'UP NEXT'), (1, 'LYRICS'), (2, 'RELATED')])
        Expanded(
          child: TextButton(
            onPressed: () => _Sheet.open(context, k),
            child: Text(name, style: Look.cond(13.5, color: Look.cream, spacing: 1.6)),
          ),
        ),
    ]);
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.tab});

  final int tab;

  static Future<void> open(BuildContext context, int tab) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        builder: (_) => _Sheet(tab: tab),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.4,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scroll) => TintBuilder(
        builder: (context, tint) => Container(
          decoration: BoxDecoration(
            color: shade(tint, 0.2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: DefaultTabController(
            length: 3,
            initialIndex: tab,
            child: StreamBuilder<MediaItem?>(
              stream: App.audio.mediaItem,
              initialData: App.audio.mediaItem.valueOrNull,
              builder: (context, _) {
                final t = App.audio.current;
                return Column(children: [
                  const SizedBox(height: 8),
                  Container(width: 36, height: 4, decoration: BoxDecoration(color: Look.edge, borderRadius: BorderRadius.circular(2))),
                  TabBar(
                    indicatorColor: Look.cream,
                    labelColor: Look.cream,
                    unselectedLabelColor: Look.cream.withValues(alpha: 0.55),
                    dividerColor: Colors.transparent,
                    labelStyle: Look.cond(14, spacing: 1.6),
                    tabs: const [Tab(text: 'UP NEXT'), Tab(text: 'LYRICS'), Tab(text: 'RELATED')],
                  ),
                  Expanded(
                    child: t == null
                        ? const SizedBox()
                        : TabBarView(children: [
                            _UpNext(scroll: scroll),
                            LyricsView(track: t),
                            _Related(track: t),
                          ]),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// What plays after this: tap a song to jump to it, drag one to move it, swipe one away. In a room,
/// the room's queue.
class _UpNext extends StatelessWidget {
  const _UpNext({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final together = App.together;
    if (together.room != null) {
      return ListenableBuilder(
        listenable: together,
        builder: (context, _) {
          final up = rooms.upcoming(together.state);
          if (up.isEmpty) {
            return Center(child: Text('Nothing waits in the room. Add songs from their menu.', style: Look.ui(14.5, color: Look.muted)));
          }
          return ListView.builder(
            controller: scroll,
            itemCount: up.length,
            itemBuilder: (context, k) {
              final t = Track.fromJson(up[k]['t']);
              if (t == null) return const SizedBox.shrink();
              final row = SongRow(track: t, onTap: () => together.playKey('${up[k]['k']}'));
              if (!together.canSteer) return row;
              return Dismissible(
                key: ValueKey('${up[k]['k']}'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => together.removeKey('${up[k]['k']}'),
                background: const ColoredBox(color: Colors.black26),
                child: row,
              );
            },
          );
        },
      );
    }
    final audio = App.audio;
    return StreamBuilder(
      stream: audio.views,
      builder: (context, _) {
        final view = audio.view;
        if (view.songs.isEmpty) return Center(child: Text('Nothing in the queue.', style: Look.ui(15, color: Look.muted)));
        final after = view.songs.length - view.index - 1;
        final shuffled = audio.player.shuffleModeEnabled;
        return NowPlayingBuilder(
          builder: (context, item, playing) => CustomScrollView(controller: scroll, slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  after <= 0
                      ? (audio.autoplay ? 'Next: songs like this one' : 'That was the last one')
                      : '${audio.from.isEmpty ? 'Next up' : 'Playing from ${audio.from}'}  ·  $after more',
                  style: Look.ui(13.5, color: Look.cream.withValues(alpha: 0.7)),
                ),
              ),
            ),
            if (view.current != null)
              SliverToBoxAdapter(
                child: SongRow(track: view.current!, current: true, playing: playing, onTap: () {}),
              ),
            SliverReorderableList(
              itemCount: max(0, after),
              onReorderItem: (from, to) {
                if (!shuffled) audio.moveShown(view.index + 1 + from, view.index + 1 + to);
              },
              itemBuilder: (context, k) {
                final i = view.index + 1 + k;
                final t = view.songs[i];
                return Dismissible(
                  key: ValueKey('${t.id}-$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.black26,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.remove_circle_outline_rounded, color: Look.cream),
                  ),
                  onDismissed: (_) => audio.removeShown(i),
                  child: Row(children: [
                    Expanded(child: SongRow(track: t, onTap: () => audio.playShown(i))),
                    if (!shuffled)
                      ReorderableDragStartListener(
                        index: k,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 14, left: 2),
                          child: Icon(Icons.drag_handle_rounded, color: Look.faint),
                        ),
                      ),
                  ]),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ]),
        );
      },
    );
  }
}

/// Songs and artists YouTube Music puts next to this one.
class _Related extends StatefulWidget {
  const _Related({required this.track});

  final Track track;

  @override
  State<_Related> createState() => _RelatedState();
}

class _RelatedState extends State<_Related> {
  late Future<List<Shelf>> _shelves = _load();

  @override
  void didUpdateWidget(_Related old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) _shelves = _load();
  }

  Future<List<Shelf>> _load() async {
    if (widget.track.src != 'yt') return const [];
    final next = await Music.next(widget.track.ref);
    if (next.related.isEmpty) return const [];
    return Music.related(next.related);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Shelf>>(
      future: _shelves,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final shelves = snap.data ?? const [];
        if (shelves.isEmpty) {
          return Center(child: Text('Nothing related turned up.', style: Look.ui(15, color: Look.muted)));
        }
        return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
          for (final s in shelves) ...[
            SectionTitle(s.title),
            if (s.items.every((i) => i.playable))
              for (final it in s.items.take(8)) ItemRow(it, list: s.items)
            else
              CardRow(s.items, width: s.items.first.kind == Kind.artist ? 120 : 140),
          ],
        ]);
      },
    );
  }
}
