/// The words of the song that plays. Synced ones light up line by line and scroll along by themselves
/// (a tap on a line jumps there); plain ones are just there to read.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import '../lyrics.dart';
import '../model.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.track, this.scroll});

  final Track track;
  final ScrollController? scroll;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late Future<Lyrics?> _words = LyricsFinder.the.of(widget.track);
  final _here = GlobalKey();
  int _line = -2;
  late final ScrollController _scroll = widget.scroll ?? ScrollController();

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) {
      _words = LyricsFinder.the.of(widget.track);
      _line = -2;
    }
  }

  @override
  void dispose() {
    if (widget.scroll == null) _scroll.dispose();
    super.dispose();
  }

  void _follow(int line, Lyrics l) {
    if (line == _line) return;
    _line = line;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _here.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      } else if (_scroll.hasClients && line >= 0) {
        // far away (after a jump): near it first, the exact place on the next line
        _scroll.jumpTo(min(line * 46.0, _scroll.position.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Lyrics?>(
      future: _words,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final l = snap.data;
        if (l == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text("No lyrics for this one.\nlrclib and YouTube Music don't have them.",
                  textAlign: TextAlign.center, style: Look.ui(15, color: Look.muted, height: 1.5)),
            ),
          );
        }
        if (!l.synced) {
          return ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(24, 12, 24, 40), children: [
            Text(l.lines.join('\n'), style: Look.ui(19, weight: FontWeight.w700, height: 1.55)),
            const SizedBox(height: 18),
            if (l.source.isNotEmpty) Text('Lyrics: ${l.source}', style: Look.ui(12.5, color: Look.faint)),
          ]);
        }
        return StreamBuilder<Duration>(
          stream: App.audio.position,
          builder: (context, pos) {
            final ms = (pos.data ?? Duration.zero).inMilliseconds + 250; // a quarter second early reads better
            final line = l.lineAt(ms);
            _follow(line, l);
            return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 220),
              itemCount: l.lines.length + 1,
              itemBuilder: (context, k) {
                if (k == l.lines.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Text(l.source.isEmpty ? '' : 'Lyrics: ${l.source}', style: Look.ui(12.5, color: Look.faint)),
                  );
                }
                final on = k == line;
                final past = k < line;
                return GestureDetector(
                  key: on ? _here : null,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => App.audio.seek(Duration(milliseconds: l.times[k])),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 260),
                      style: Look.ui(on ? 25 : 22,
                          weight: FontWeight.w800,
                          height: 1.25,
                          color: on ? Look.cream : (past ? Look.cream.withValues(alpha: 0.45) : Look.cream.withValues(alpha: 0.28))),
                      child: Text(l.lines[k]),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
