/// The frame around every page: three tabs (Home, Search, Your tapes), each with its own pages, and the
/// little player above them that opens the big one.
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
import 'search.dart';
import 'widgets.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  /// Switches to a tab from anywhere (Home's "See all" goes to Your tapes, say).
  static void goTo(BuildContext context, int tab) => context.findAncestorStateOfType<_ShellState>()?._go(tab);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _keys = List.generate(3, (_) => GlobalKey<NavigatorState>());
  StreamSubscription<String>? _notices;

  static const _pages = <Widget>[HomePage(), SearchPage(), LibraryPage()];

  @override
  void initState() {
    super.initState();
    _notices = App.audio.notices.stream.listen((m) {
      if (mounted) say(context, m);
    });
  }

  @override
  void dispose() {
    _notices?.cancel();
    super.dispose();
  }

  void _go(int tab) {
    if (tab == _tab) {
      _keys[tab].currentState?.popUntil((r) => r.isFirst); // the tab again: back to its first page
    } else {
      setState(() => _tab = tab);
    }
  }

  void _back() {
    final nav = _keys[_tab].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else if (_tab != 0) {
      setState(() => _tab = 0);
    } else {
      SystemNavigator.pop(); // the music keeps playing in its service
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            for (var k = 0; k < 3; k++)
              HeroControllerScope.none(
                child: Navigator(
                  key: _keys[k],
                  onGenerateRoute: (s) => MaterialPageRoute<void>(settings: s, builder: (_) => _pages[k]),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _go,
            backgroundColor: Look.side,
            indicatorColor: Look.accent.withValues(alpha: 0.18),
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded, color: Look.accent), label: 'Home'),
              NavigationDestination(
                  icon: const Icon(Icons.search_rounded), selectedIcon: Icon(Icons.search_rounded, color: Look.accent), label: 'Search'),
              NavigationDestination(
                  icon: const Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded, color: Look.accent),
                  label: 'Your tapes'),
            ],
          ),
        ]),
      ),
    );
  }
}

/// The song that plays, above the tabs: tap it for the big player.
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
        return Material(
          color: Look.raised,
          child: InkWell(
            onTap: () => NowPlaying.open(context),
            child: SizedBox(
              height: 62,
              child: Stack(children: [
                Positioned(left: 0, right: 0, top: 0, child: _Progress(track: t)),
                Row(children: [
                  const SizedBox(width: 10),
                  Cover(t, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(14.5, weight: FontWeight.w600)),
                      Text(item.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(12.5, color: Look.muted)),
                    ]),
                  ),
                  const PlayButton(size: 44, filled: false),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: App.audio.skipToNext,
                    icon: const Icon(Icons.skip_next_rounded, color: Look.cream, size: 28),
                  ),
                  const SizedBox(width: 4),
                ]),
              ]),
            ),
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
        final f = total.inMilliseconds <= 0 ? 0.0 : (snap.data ?? Duration.zero).inMilliseconds / total.inMilliseconds;
        return LinearProgressIndicator(
          value: f.clamp(0.0, 1.0),
          minHeight: 2,
          backgroundColor: Colors.transparent,
          color: Look.accent,
        );
      },
    );
  }
}

/// Play and pause in one button, with a ring turning around it while the song loads.
class PlayButton extends StatelessWidget {
  const PlayButton({super.key, this.size = 64, this.filled = true});

  final double size;
  final bool filled;

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
        final icon = Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: size * (filled ? 0.5 : 0.62), color: filled ? Look.bg : Look.cream);
        return SizedBox.square(
          dimension: size,
          child: Stack(alignment: Alignment.center, children: [
            if (filled)
              Material(
                color: Look.accent,
                shape: const CircleBorder(),
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
                  child: CircularProgressIndicator(strokeWidth: filled ? 3 : 2.2, color: filled ? Look.cream : Look.accent),
                ),
              ),
          ]),
        );
      },
    );
  }
}
