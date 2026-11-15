/// Samples: one song at a time on the whole screen, from its best half minute, round and round until
/// you flick to the next one (like TikTok, like YouTube Music's Samples). Like it, put it on a tape, play
/// the whole song, or say you're not interested. The music that was on waits and carries on after.
library;

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
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
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            PageView.builder(
              controller: _pages,
              scrollDirection: Axis.vertical,
              itemCount: feed.items.length,
              onPageChanged: (k) {
                if (_shown) feed.show(k);
              },
              itemBuilder: (context, k) => _SampleCard(sample: feed.items[k], feed: feed, here: k == feed.index),
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

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.sample, required this.feed, required this.here});

  final Sample sample;
  final Samples feed;
  final bool here;

  @override
  Widget build(BuildContext context) {
    final t = sample.track;
    final size = MediaQuery.sizeOf(context);
    final side = min(size.width * 0.78, size.height * 0.46);
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
              colors: [Color(0x66000000), Color(0x22000000), Color(0xDD000000)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.28),
          child: AnimatedScale(
            scale: here && !feed.paused ? 1 : 0.92,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            child: DecoratedBox(
              decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 40, offset: Offset(0, 18))]),
              child: Cover(t, size: side, radius: 14),
            ),
          ),
        ),
        if (here && feed.paused)
          const Align(
            alignment: Alignment(0, -0.28),
            child: Icon(Icons.play_arrow_rounded, size: 84, color: Colors.white70),
          ),
        Positioned(
          left: 20,
          right: 84,
          bottom: MediaQuery.paddingOf(context).bottom + 28,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(24, weight: FontWeight.w900, height: 1.15)),
            const SizedBox(height: 4),
            Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(16, color: Look.cream.withValues(alpha: 0.8))),
            const SizedBox(height: 14),
            if (here) _ClipProgress(feed: feed, sample: sample),
          ]),
        ),
        Positioned(
          right: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
          child: Column(children: [
            ListenableBuilder(
              listenable: App.library,
              builder: (context, _) {
                final liked = App.library.isLiked(t);
                return _Side(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, liked ? 'Liked' : 'Like',
                    () => App.library.toggleLike(t),
                    color: liked ? Look.accent : null);
              },
            ),
            _Side(Icons.library_add_rounded, 'Tape', () => pickTape(context, [t])),
            _Side(Icons.play_circle_fill_rounded, 'Play it', () async {
              await feed.stop();
              await App.audio.playSongs([t], from: 'Samples');
              Shell.goTo(0);
            }),
            _Side(Icons.ios_share_rounded, 'Share', () => shareSong(context, t)),
            _Side(Icons.do_not_disturb_on_outlined, 'Not for me', () {
              App.library.hide(t, true);
              say(context, "Got it. Songs like that come up less, and this one doesn't anymore.");
            }),
          ]),
        ),
      ]),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side(this.icon, this.text, this.onTap, {this.color});

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Column(children: [
          Icon(icon, size: 34, color: color ?? Colors.white, shadows: const [Shadow(color: Colors.black54, blurRadius: 12)]),
          const SizedBox(height: 3),
          Text(text, style: Look.ui(11.5, weight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
    );
  }
}

/// How far into its half minute the sample is.
class _ClipProgress extends StatelessWidget {
  const _ClipProgress({required this.feed, required this.sample});

  final Samples feed;
  final Sample sample;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: feed.player.positionStream,
      builder: (context, snap) {
        final start = (sample.start ?? 0) * 1000;
        final at = (snap.data ?? Duration.zero).inMilliseconds - start;
        final f = (at / (Samples.length * 1000)).clamp(0.0, 1.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 3,
            backgroundColor: Colors.white24,
            color: Look.cream,
          ),
        );
      },
    );
  }
}
