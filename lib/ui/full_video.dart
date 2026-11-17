/// The music video over the whole screen, the phone turned on its side and the bars out of the way: the
/// same video as on the big player (one video player for both, video_view.dart keeps it in step with the
/// song). A tap brings the song's keys over it for a few seconds; a double tap on the left or the right
/// jumps 10 seconds back or ahead. The screen stays on meanwhile.
library;

import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mixtape_native/mixtape_native.dart';
import 'package:video_player/video_player.dart';

import '../app.dart';
import '../look.dart';
import '../model.dart';
import 'turning.dart';
import 'video_view.dart';

class FullVideo extends StatefulWidget {
  const FullVideo({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, a, b) => const FullVideo(),
        transitionsBuilder: (context, a, b, child) => FadeTransition(opacity: a, child: child),
      ));

  @override
  State<FullVideo> createState() => _FullVideoState();
}

class _FullVideoState extends State<FullVideo> {
  bool _keys = true; // the keys show over the video
  bool _keysThere = true; // they're on the page (shown, or still fading away)
  Timer? _hide;
  double _tapAt = 0.5; // where across the screen the last double tap was
  int _jumped = 0; // the last double tap's jump in seconds, shown for a moment
  Timer? _jumpGone;
  double? _dragging; // where the slider is held, in seconds

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    MixtapeNative.keepAwake(true).ignore();
    _hideLater();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _jumpGone?.cancel();
    MixtapeNative.keepAwake(false).ignore();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    appTurning(force: true);
    super.dispose();
  }

  /// The keys go away by themselves a few seconds after the last touch (not while the song is paused).
  void _hideLater() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _dragging == null && App.audio.player.playing) setState(() => _keys = false);
    });
  }

  void _tap() {
    setState(() {
      _keys = !_keys;
      if (_keys) _keysThere = true;
    });
    if (_keys) _hideLater();
  }

  void _doubleTap() {
    final back = _tapAt < 0.4, ahead = _tapAt > 0.6;
    if (!back && !ahead) {
      _tap(); // the middle: just the keys
      return;
    }
    final p = App.audio.player;
    final end = p.duration;
    var to = p.position + Duration(seconds: back ? -10 : 10);
    if (to < Duration.zero) to = Duration.zero;
    if (end != null && to > end) to = end;
    App.audio.seek(to).ignore();
    _jumpGone?.cancel();
    setState(() => _jumped = back ? -10 : 10);
    _jumpGone = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _jumped = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // the video (or what shows while there's none), and the taps on it
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          onDoubleTapDown: (d) => _tapAt = d.localPosition.dx / max(1.0, MediaQuery.sizeOf(context).width),
          onDoubleTap: _doubleTap,
          child: ValueListenableBuilder(
            valueListenable: VideoView.now,
            builder: (context, now, _) {
              final c = now.player;
              if (c != null && c.value.isInitialized) {
                return Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)));
              }
              // above the middle, where the song's keys don't cover it
              return Align(alignment: const Alignment(0, -0.42), child: VideoWords(state: now.state));
            },
          ),
        ),
        if (_jumped != 0)
          IgnorePointer(
            child: Align(
              alignment: Alignment(_jumped < 0 ? -0.62 : 0.62, 0),
              child: _Bubble(back: _jumped < 0),
            ),
          ),
        if (_keysThere)
          AnimatedOpacity(
            opacity: _keys ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            onEnd: () {
              if (!_keys && mounted) setState(() => _keysThere = false);
            },
            child: IgnorePointer(ignoring: !_keys, child: _over(context)),
          ),
      ]),
    );
  }

  /// The keys over the video: the song at the top, back, play and next in the middle, where it is at the
  /// bottom with the way out of the full screen. Only the keys take touches: the rest goes to the video.
  Widget _over(BuildContext context) {
    final audio = App.audio;
    return Stack(fit: StackFit.expand, children: [
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.62), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: 0.7)],
              stops: const [0, 0.3, 0.62, 1],
            ),
          ),
        ),
      ),
      SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 10, 18, 6),
        child: StreamBuilder<MediaItem?>(
          stream: audio.mediaItem,
          initialData: audio.mediaItem.valueOrNull,
          builder: (context, _) {
            final t = audio.current;
            return Column(children: [
              if (t != null)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(19, weight: FontWeight.w800)),
                      Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Look.ui(14.5, color: Look.cream.withValues(alpha: 0.75))),
                    ]),
                  ),
                ]),
              const Spacer(),
              StreamBuilder<bool>(
                stream: audio.player.playingStream,
                initialData: audio.player.playing,
                builder: (context, snap) {
                  final playing = snap.data ?? false;
                  return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Round(Icons.skip_previous_rounded, 'Back', size: 34, onTap: () {
                      audio.skipToPrevious();
                      _hideLater();
                    }),
                    const SizedBox(width: 34),
                    _Round(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, playing ? 'Pause' : 'Play', size: 44,
                        onTap: () {
                      if (playing) {
                        audio.pause();
                      } else {
                        audio.play();
                      }
                      _hideLater();
                    }),
                    const SizedBox(width: 34),
                    _Round(Icons.skip_next_rounded, 'Next', size: 34, onTap: () {
                      audio.skipToNext();
                      _hideLater();
                    }),
                  ]);
                },
              ),
              const Spacer(),
              _where(t),
            ]);
          },
        ),
      ),
    ]);
  }

  /// Where the song is, to drag, and the key out of the full screen.
  Widget _where(Track? t) {
    final audio = App.audio;
    return StreamBuilder<Duration>(
      stream: audio.position,
      builder: (context, snap) {
        final total = (audio.player.duration ?? Duration(seconds: t?.dur ?? 0)).inMilliseconds / 1000;
        final now = (snap.data ?? Duration.zero).inMilliseconds / 1000;
        final double shown = min(max(_dragging ?? now, 0.0), max(total, 0.0));
        final time = Look.cond(14, color: Look.cream, spacing: 0.8);
        return Row(children: [
          Text(clock(shown.round()), style: time),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Look.cream,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.24),
                thumbColor: Look.cream,
              ),
              child: Slider(
                value: total <= 0 ? 0.0 : shown,
                max: total <= 0 ? 1.0 : total,
                onChanged: total <= 0
                    ? null
                    : (v) {
                        _hide?.cancel();
                        setState(() => _dragging = v);
                      },
                onChangeEnd: (v) {
                  audio.seek(Duration(milliseconds: (v * 1000).round()));
                  setState(() => _dragging = null);
                  _hideLater();
                },
              ),
            ),
          ),
          Text(total <= 0 ? '' : clock(total.round()), style: time),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Leave full screen',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 30),
          ),
        ]);
      },
    );
  }
}

/// A key in a dark round, for the middle of the full screen.
class _Round extends StatelessWidget {
  const _Round(this.icon, this.tip, {required this.size, required this.onTap});

  final IconData icon;
  final String tip;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tip,
          padding: EdgeInsets.all(size * 0.32),
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white, size: size),
        ),
      );
}

/// "10 seconds back" or "ahead" for a moment, where the double tap was.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.back});

  final bool back;

  @override
  Widget build(BuildContext context) => Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
        child: Icon(back ? Icons.replay_10_rounded : Icons.forward_10_rounded, color: Colors.white, size: 44),
      );
}
