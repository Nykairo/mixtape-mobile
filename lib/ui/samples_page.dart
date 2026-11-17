/// Samples: one song at a time on the whole screen, from its best half minute, round and round until
/// you flick to the next one (like TikTok, like YouTube Music's Samples). Like it, put it on a tape, play
/// the whole song, or say you're not interested. The music that was on waits and carries on after.
library;

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import '../music.dart';
import '../samples.dart';
import 'shell.dart';
import 'widgets.dart';

class SamplesPage extends StatefulWidget {
  const SamplesPage({super.key});

  @override
  State<SamplesPage> createState() => _SamplesPageState();
}

class _SamplesPageState extends State<SamplesPage> {
  final _pages = PageController();
  bool _shown = false;
  bool _wasPlaying = false;
  Samples? _feed;

  @override
  void initState() {
    super.initState();
    Shell.tab.addListener(_tabChanged);
    _tabChanged();
  }

  @override
  void dispose() {
    Shell.tab.removeListener(_tabChanged);
    _pages.dispose();
    super.dispose();
  }

  /// Samples plays only while its tab shows: opening it pauses the music, leaving it brings it back.
  Future<void> _tabChanged() async {
    final on = Shell.tab.value == 1;
    if (on == _shown) return;
    _shown = on;
    if (on) {
      final feed = _feed ??= App.samples;
      _wasPlaying = App.audio.player.playing;
      if (_wasPlaying) await App.audio.pause();
      if (feed.items.isEmpty) await feed.more();
      final k = _pages.hasClients ? (_pages.page ?? 0).round() : 0;
      await feed.show(k < feed.items.length ? k : 0);
    } else {
      await _feed?.stop();
      if (_wasPlaying) await App.audio.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    if (feed == null) return const ColoredBox(color: Colors.black);
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        if (feed.items.isEmpty) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: feed.loading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(feed.trouble ?? 'Nothing here yet.',
                            textAlign: TextAlign.center, style: Look.ui(16, color: Look.muted, height: 1.4)),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: feed.more, child: const Text('Try again')),
                      ]),
                    ),
            ),
          );
        }
        // the cards flick above the tabs, never under them
        final tabs = MediaQuery.paddingOf(context).bottom;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            Padding(
              padding: EdgeInsets.only(bottom: tabs),
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: PageView.builder(
                  controller: _pages,
                  scrollDirection: Axis.vertical,
                  itemCount: feed.items.length,
                  onPageChanged: (k) {
                    if (_shown) feed.show(k);
                  },
                  itemBuilder: (context, k) => _SampleCard(sample: feed.items[k], feed: feed, here: k == feed.index),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Row(children: [
                  Text('Samples', style: Look.ui(22, weight: FontWeight.w900)),
                  const Spacer(),
                  Icon(Icons.swipe_vertical_rounded, color: Look.cream.withValues(alpha: 0.6), size: 20),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// One artist's Samples, over the whole screen: their songs one after another, each from its best
/// half minute. The music that was on waits, and carries on when this closes.
class ArtistSamplesPage extends StatefulWidget {
  const ArtistSamplesPage({super.key, required this.artist});

  final ArtistPage artist;

  static Future<void> open(BuildContext context, ArtistPage a) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ArtistSamplesPage(artist: a)));

  @override
  State<ArtistSamplesPage> createState() => _ArtistSamplesPageState();
}

class _ArtistSamplesPageState extends State<ArtistSamplesPage> {
  late final Samples _feed = Samples.artist(widget.artist, unwanted: App.library.isHidden);
  final _pages = PageController();
  bool _wasPlaying = false;
  bool _left = false; // a song of theirs was played: that one goes on, not the music from before

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _wasPlaying = App.audio.player.playing;
    if (_wasPlaying) await App.audio.pause();
    await _feed.more();
    if (mounted && _feed.items.isNotEmpty) await _feed.show(0);
  }

  @override
  void dispose() {
    final feed = _feed;
    feed.stop().whenComplete(feed.dispose).ignore();
    if (_wasPlaying && !_left) App.audio.play().ignore();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _feed,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          if (_feed.items.isEmpty)
            Center(
              child: _feed.loading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(_feed.trouble ?? 'Nothing here yet.',
                          textAlign: TextAlign.center, style: Look.ui(16, color: Look.muted, height: 1.4)),
                    ),
            )
          else
            PageView.builder(
              controller: _pages,
              scrollDirection: Axis.vertical,
              itemCount: _feed.items.length,
              onPageChanged: _feed.show,
              itemBuilder: (context, k) => _SampleCard(
                sample: _feed.items[k],
                feed: _feed,
                here: k == _feed.index,
                leave: () {
                  _left = true;
                  Navigator.of(context).pop();
                },
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 4, 0),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('SAMPLES', style: Look.cond(12, color: Look.cream.withValues(alpha: 0.7), spacing: 2)),
                    Text(widget.artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(22, weight: FontWeight.w900)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.sample, required this.feed, required this.here, this.leave});

  final Sample sample;
  final Samples feed;
  final bool here;

  /// Where "Play it" goes afterwards: the player; by default Home with the song playing.
  final VoidCallback? leave;

  @override
  Widget build(BuildContext context) {
    final t = sample.track;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return GestureDetector(
      onTap: feed.toggle,
      onDoubleTap: () {
        if (!App.library.isLiked(t)) App.library.toggleLike(t);
        say(context, 'In your liked songs');
      },
      child: Stack(fit: StackFit.expand, children: [
        // the cover, blown up and blurred, as the backdrop
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Opacity(opacity: 0.55, child: Cover(t, size: size.height, radius: 0)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x22000000), Color(0xCC000000), Color(0xFF000000)],
              stops: [0, 0.4, 0.82, 1],
            ),
          ),
        ),
        // top to bottom, nothing on top of anything: the cover gets the room the words and keys leave
        Padding(
          padding: EdgeInsets.fromLTRB(22, pad.top + 62, 22, pad.bottom + 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: LayoutBuilder(builder: (context, room) {
                final side = min(room.maxWidth, room.maxHeight);
                if (side < 32) return const SizedBox.shrink(); // a window too small for a cover
                return Center(
                  child: AnimatedScale(
                    scale: here && !feed.paused ? 1 : 0.92,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutBack,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 40, offset: Offset(0, 18))],
                      ),
                      child: Stack(alignment: Alignment.center, children: [
                        Cover(t, size: side, radius: 14),
                        if (here && feed.paused) const Icon(Icons.play_arrow_rounded, size: 84, color: Colors.white70),
                      ]),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(24, weight: FontWeight.w900, height: 1.15)),
            const SizedBox(height: 4),
            Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(16, color: Look.cream.withValues(alpha: 0.8))),
            const SizedBox(height: 14),
            if (here) _ClipProgress(feed: feed) else const SizedBox(height: 3),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: App.library,
                  builder: (context, _) {
                    final liked = App.library.isLiked(t);
                    return _Key(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, liked ? 'Liked' : 'Like',
                        () => App.library.toggleLike(t),
                        color: liked ? Look.accent : null);
                  },
                ),
              ),
              Expanded(child: _Key(Icons.library_add_rounded, 'Tape', () => pickTape(context, [t]))),
              Expanded(
                child: _Key(Icons.play_circle_fill_rounded, 'Play it', () async {
                  await feed.stop();
                  await App.audio.playSongs([t], from: 'Samples');
                  final away = leave;
                  if (away != null) {
                    away();
                  } else {
                    Shell.goTo(0);
                  }
                }),
              ),
              Expanded(child: _Key(Icons.ios_share_rounded, 'Share', () => shareSong(context, t))),
              Expanded(
                child: _Key(Icons.do_not_disturb_on_outlined, 'Not for me', () {
                  App.library.hide(t, true);
                  say(context, "Got it. Songs like that come up less, and this one doesn't anymore.");
                }),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// One of the keys in the row under a sample: a big icon with its word.
class _Key extends StatelessWidget {
  const _Key(this.icon, this.text, this.onTap, {this.color});

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 30, color: color ?? Colors.white, shadows: const [Shadow(color: Colors.black54, blurRadius: 12)]),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, maxLines: 1, style: Look.ui(11.5, weight: FontWeight.w700, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}

/// How far into its half minute the sample is: the sample that plays says so itself (Samples.progress),
/// whichever of its two players has it.
class _ClipProgress extends StatelessWidget {
  const _ClipProgress({required this.feed});

  final Samples feed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: feed.progress,
      builder: (context, f, _) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(value: f, minHeight: 3, backgroundColor: Colors.white24, color: Look.cream),
      ),
    );
  }
}
