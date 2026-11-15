/// The frame around every page: four tabs (Home, Samples, Search, Library), each with its own pages, the
/// little player above them (in the color of what plays; swipe it for the next or the last song), and
/// a strip that says when you're in a room or listening along.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../look.dart';
import '../model.dart';
import 'home.dart';
import 'library_page.dart';
import 'now_playing.dart';
import 'samples_page.dart';
import 'search.dart';
import 'tint.dart';
import 'together_page.dart';
import 'widgets.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  static final stateKey = GlobalKey<ShellState>();

  /// Which tab shows (Samples plays only while it does).
  static final tab = ValueNotifier<int>(0);

  /// Opens a page on the tab that shows, from anywhere (the big player closes for it).
  static void push(Widget page) => stateKey.currentState?._push(page);

  /// Switches to a tab from anywhere (Home's "See all" goes to the library, say).
  static void goTo(int tab) => stateKey.currentState?._go(tab);

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int _tab = 0;
  final _keys = List.generate(4, (_) => GlobalKey<NavigatorState>());
  final _subs = <StreamSubscription<Object?>>[];

  static const _pages = <Widget>[HomePage(), SamplesPage(), SearchPage(), LibraryPage()];

  @override
  void initState() {
    super.initState();
    for (final news in [App.audio.notices.stream, App.downloads.notices.stream, App.together.notices.stream]) {
      _subs.add(news.listen((m) {
        if (mounted) say(context, m);
      }));
    }
    _subs.add(App.audio.mediaItem.listen((_) => Tint.follow(App.audio.current)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _go(int tab) {
    if (tab == _tab) {
      _keys[tab].currentState?.popUntil((r) => r.isFirst); // the tab again: back to its first page
    } else {
      setState(() => _tab = tab);
      Shell.tab.value = tab;
    }
  }

  void _push(Widget page) {
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    _keys[_tab].currentState?.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _back() {
    final nav = _keys[_tab].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else if (_tab != 0) {
      _go(0);
    } else {
      SystemNavigator.pop(); // the music keeps playing in its service
    }
  }

  @override
  Widget build(BuildContext context) {
    final samples = _tab == 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _tab,
          children: [
            for (var k = 0; k < 4; k++)
              HeroControllerScope.none(
                child: Navigator(
                  key: _keys[k],
                  onGenerateRoute: (s) => MaterialPageRoute<void>(settings: s, builder: (_) => _pages[k]),
                ),
              ),
          ],
        ),
        // Samples plays under a see-through bar; everywhere else the bar is solid, with a short fade
        // above it, so a list never shows through the tabs or behind the phone's own keys
        bottomNavigationBar: samples
            ? _NavBar(tab: _tab, onTap: _go, dark: true)
            : Column(mainAxisSize: MainAxisSize.min, children: [
                IgnorePointer(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Look.bg.withValues(alpha: 0), Look.bg],
                      ),
                    ),
                  ),
                ),
                ColoredBox(
                  color: Look.bg,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const _TogetherStrip(),
                    const MiniPlayer(),
                    _NavBar(tab: _tab, onTap: _go, dark: false),
                  ]),
                ),
              ]),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.tab, required this.onTap, required this.dark});

  final int tab;
  final ValueChanged<int> onTap;
  final bool dark;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'Samples'),
    (Icons.search_rounded, Icons.manage_search_rounded, 'Search'),
    (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [Colors.black.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.85)]
              : [Look.bg, Look.bg],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom, top: 4),
        child: Row(children: [
          for (var k = 0; k < _items.length; k++)
            Expanded(
              child: InkResponse(
                onTap: () => onTap(k),
                radius: 36,
                child: SizedBox(
                  height: 56,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AnimatedScale(
                      scale: k == tab ? 1.08 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(k == tab ? _items[k].$2 : _items[k].$1,
                          color: k == tab ? Look.cream : Look.muted, size: 25),
                    ),
                    const SizedBox(height: 3),
                    Text(_items[k].$3,
                        style: Look.ui(11.5,
                            weight: k == tab ? FontWeight.w700 : FontWeight.w500,
                            color: k == tab ? Look.cream : Look.muted)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// In a room, or listening along: what and with whom, a tap away from the room's page.
class _TogetherStrip extends StatelessWidget {
  const _TogetherStrip();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.together,
      builder: (context, _) {
        final t = App.together;
        if (t.room == null && t.friend.isEmpty) return const SizedBox.shrink();
        final text = t.room != null
            ? '${t.party ? 'Party' : 'Room'} ${t.code}  ·  ${t.here.length <= 1 ? 'just you so far' : '${t.here.length} listening'}'
            : 'Listening along with ${t.friendName}';
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Material(
            color: Look.accent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => TogetherPage.open(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(children: [
                  const Icon(Icons.groups_rounded, size: 18, color: Look.bg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, weight: FontWeight.w700, color: Look.bg)),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: Look.bg),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The song that plays, above the tabs, in its cover's color: tap it for the big player, swipe it for
/// the next song (or back).
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: App.audio.mediaItem,
      initialData: App.audio.mediaItem.valueOrNull,
      builder: (context, snap) {
        final item = snap.data;
        final t = App.audio.current;
        if (item == null || t == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
          child: TintBuilder(
            builder: (context, tint) => Material(
              color: shade(tint, 0.3),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => NowPlaying.open(context),
                child: GestureDetector(
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -250) App.audio.skipToNext();
                    if (v > 250) App.audio.skipToPrevious();
                  },
                  child: SizedBox(
                    height: 60,
                    child: Stack(children: [
                      Row(children: [
                        const SizedBox(width: 8),
                        Cover(t, size: 44, radius: 6),
                        const SizedBox(width: 11),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            transitionBuilder: (child, a) => FadeTransition(
                              opacity: a,
                              child: SlideTransition(
                                position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(a),
                                child: child,
                              ),
                            ),
                            child: Column(
                              key: ValueKey(t.id),
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(14.5, weight: FontWeight.w700)),
                                Text(item.artist ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Look.ui(12.5, color: Look.cream.withValues(alpha: 0.7))),
                              ],
                            ),
                          ),
                        ),
                        _Heart(track: t),
                        const PlayButton(size: 44, filled: false),
                        const SizedBox(width: 4),
                      ]),
                      Positioned(left: 8, right: 8, bottom: 0, child: _Progress(track: t)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Heart extends StatelessWidget {
  const _Heart({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.library,
      builder: (context, _) {
        final liked = App.library.isLiked(track);
        return IconButton(
          tooltip: liked ? 'Unlike' : 'Like',
          onPressed: () => App.library.toggleLike(track),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(liked), color: liked ? Look.accent : Look.cream),
          ),
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: App.audio.position,
      builder: (context, snap) {
        final total = App.audio.player.duration ?? Duration(seconds: track.dur);
        final ms = total.inMilliseconds;
        final f = ms <= 0 ? 0.0 : (snap.data ?? Duration.zero).inMilliseconds / ms;
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: f < 0 ? 0 : (f > 1 ? 1 : f),
            minHeight: 2,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            color: Look.cream,
          ),
        );
      },
    );
  }
}

/// Play and pause in one button, with a ring turning around it while the song loads.
class PlayButton extends StatelessWidget {
  const PlayButton({super.key, this.size = 64, this.filled = true, this.color});

  final double size;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: App.audio.playbackState,
      initialData: App.audio.playbackState.valueOrNull,
      builder: (context, snap) {
        final s = snap.data;
        final playing = s?.playing ?? false;
        final waiting = playing &&
            (s?.processingState == AudioProcessingState.loading || s?.processingState == AudioProcessingState.buffering);
        final face = color ?? Look.cream;
        final icon = Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: size * (filled ? 0.52 : 0.62), color: filled ? Look.bg : Look.cream);
        return SizedBox.square(
          dimension: size,
          child: Stack(alignment: Alignment.center, children: [
            if (filled)
              Material(
                color: face,
                shape: const CircleBorder(),
                elevation: 4,
                shadowColor: Colors.black54,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: playing ? App.audio.pause : App.audio.play,
                  child: SizedBox.square(dimension: size, child: Center(child: icon)),
                ),
              )
            else
              IconButton(
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: playing ? App.audio.pause : App.audio.play,
                icon: icon,
              ),
            if (waiting)
              IgnorePointer(
                child: SizedBox.square(
                  dimension: size - (filled ? 0 : 8),
                  child: CircularProgressIndicator(strokeWidth: filled ? 3 : 2.2, color: filled ? Look.accent : Look.cream),
                ),
              ),
          ]),
        );
      },
    );
  }
}
