/// Video mode on the big player: the song's music video, without sound, following the song (it starts,
/// pauses, jumps and changes speed with it). It only runs while it shows: off screen, or with the app in
/// the background, it lets go. The video of the song after this one is looked up while this one plays.
/// A key in its corner puts it over the whole screen (full_video.dart), still the same video player.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app.dart';
import '../look.dart';
import '../model.dart';
import '../video.dart';
import 'full_video.dart';
import 'widgets.dart';

class VideoView extends StatefulWidget {
  const VideoView({super.key, required this.track, required this.size});

  final Track track;
  final double size;

  /// What the video shows right now: its player (while it plays) and 'looking', 'on', 'none' or
  /// 'failed'. The whole-screen video shows the same thing from it, with the same player.
  static final now = ValueNotifier<({VideoPlayerController? player, String state})>((player: null, state: 'looking'));

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> with WidgetsBindingObserver {
  VideoPlayerController? _c;
  MusicVideo? _video;
  String _state = 'looking'; // looking, on, none, failed
  Timer? _follow;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _find();
  }

  @override
  void didUpdateWidget(VideoView old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) {
      _letGo();
      _find();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _follow?.cancel();
      _c?.pause();
    } else if (state == AppLifecycleState.resumed && _c != null) {
      _startFollowing();
    }
  }

  void _show(String state) {
    setState(() => _state = state);
    // the whole screen is another page: it hears about it a moment later, out of any build
    final c = state == 'on' ? _c : null;
    scheduleMicrotask(() => VideoView.now.value = (player: c, state: state));
  }

  Future<void> _find() async {
    final ask = ++_asked;
    _show('looking');
    try {
      final v = await Videos.find(widget.track);
      if (!mounted || ask != _asked) return;
      if (v == null) {
        _show('none');
        _readyNext();
        return;
      }
      final (url, agent) = await Videos.stream(v.id);
      if (!mounted || ask != _asked) return;
      if (url.isEmpty) {
        _show('failed');
        return;
      }
      final c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {if (agent.isNotEmpty) 'User-Agent': agent},
        // Android hands the sound to whoever plays last: a video that asks for it pauses the song, and
        // the song back on pauses the video, over and over. The video has no sound here, so it never
        // asks. (On the iPhone the song and its video share one audio session and get along as they are.)
        videoPlayerOptions: Platform.isAndroid ? VideoPlayerOptions(mixWithOthers: true) : null,
      );
      await c.initialize();
      if (!mounted || ask != _asked) {
        await c.dispose();
        return;
      }
      await c.setVolume(0);
      _video = v;
      _c = c;
      _show('on');
      _startFollowing();
      _readyNext();
    } on Object {
      if (mounted && ask == _asked) _show('failed');
    }
  }

  /// The next song's video, looked up now so it shows the moment that song starts.
  void _readyNext() {
    final next = App.audio.upNext;
    if (next != null) Videos.prepare([next]).ignore();
  }

  void _startFollowing() {
    _follow?.cancel();
    _follow = Timer.periodic(const Duration(milliseconds: 500), (_) => _step());
    _step(jump: true);
  }

  /// The video does what the song does: where it is (plus the video's intro), whether it plays, how fast.
  void _step({bool jump = false}) {
    final c = _c, v = _video;
    if (c == null || v == null || !c.value.isInitialized) return;
    final p = App.audio.player;
    final want = p.position + Duration(seconds: v.lead);
    final off = (c.value.position - want).inMilliseconds.abs();
    if (jump || off > 450 * (p.speed < 1 ? 1 : p.speed)) c.seekTo(want);
    if ((c.value.playbackSpeed - p.speed).abs() > 0.01) c.setPlaybackSpeed(p.speed);
    if (p.playing && !c.value.isPlaying) {
      c.play();
    } else if (!p.playing && c.value.isPlaying) {
      c.pause();
    }
  }

  void _letGo() {
    _follow?.cancel();
    _follow = null;
    final c = _c;
    _c = null;
    _video = null;
    if (c == null) return;
    // the whole screen lets go of it first, then it goes
    scheduleMicrotask(() {
      if (VideoView.now.value.player == c) VideoView.now.value = (player: null, state: 'looking');
      c.dispose();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _letGo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final size = widget.size;
    if (_state == 'on' && c != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: Stack(fit: StackFit.expand, children: [
                VideoPlayer(c),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.42),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Full screen',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => FullVideo.open(context),
                      icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        Opacity(opacity: 0.35, child: Cover(widget.track, size: size, radius: 12)),
        Padding(padding: const EdgeInsets.all(24), child: VideoWords(state: _state)),
      ]),
    );
  }
}

/// What shows instead of the video: still looking, or there's none, or it wouldn't load.
class VideoWords extends StatelessWidget {
  const VideoWords({super.key, required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final words = switch (state) {
      'looking' => 'Looking for the music video…',
      'none' => 'This song has no music video that goes with it',
      _ => "The music video wouldn't load",
    };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (state == 'looking')
        const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.6))
      else
        const Icon(Icons.videocam_off_outlined, color: Look.cream, size: 30),
      const SizedBox(height: 12),
      Text(words, textAlign: TextAlign.center, style: Look.ui(14.5, weight: FontWeight.w600)),
    ]);
  }
}
