/// The words of the song that plays. Synced ones light up line by line and scroll along by themselves
/// (a tap on a line jumps there); plain ones are just there to read. Translate puts each line in the
/// phone's language under it.
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

  /// The lines in the phone's language, once Translate is on.
  List<String>? _mine;
  bool _translating = false;
  late final ScrollController _scroll = widget.scroll ?? ScrollController();

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) {
      _words = LyricsFinder.the.of(widget.track);
      _line = -2;
      final on = _mine != null;
      _mine = null;
      if (on) _words.then((l) => l == null ? null : _translate(l)); // Translate stays on for the next song
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

  Future<void> _translate(Lyrics l) async {
    setState(() => _translating = true);
    final mine = await Translator.the.lines(l.lines);
    if (!mounted) return;
    setState(() {
      _translating = false;
      _mine = mine;
    });
    if (_same(mine, l.lines) && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('These words are in your language already.')));
    }
  }

  static bool _same(List<String> a, List<String> b) {
    for (var k = 0; k < a.length && k < b.length; k++) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  /// Translate (or back to only the original), over the words.
  Widget _switch(Lyrics l) {
    final on = _mine != null;
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Material(
          color: on ? Look.cream : Look.cream.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _translating ? null : () => on ? setState(() => _mine = null) : _translate(l),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _translating
                    ? SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Look.cream))
                    : Icon(Icons.translate_rounded, size: 16, color: on ? Look.bg : Look.cream),
                const SizedBox(width: 6),
                Text(on ? 'Original only' : 'Translate', style: Look.ui(13, weight: FontWeight.w700, color: on ? Look.bg : Look.cream)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// A line's translation under it, smaller and quieter (nothing when it says the same).
  Widget? _under(int k, String line, double size, Color color) {
    final mine = _mine;
    if (mine == null || k >= mine.length || mine[k].trim() == line.trim() || line == '♪') return null;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(mine[k], style: Look.ui(size, weight: FontWeight.w600, height: 1.25, color: color)),
    );
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
          return Column(children: [
            _switch(l),
            Expanded(
              child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(24, 12, 24, 40), children: [
                if (_mine == null)
                  Text(l.lines.join('\n'), style: Look.ui(19, weight: FontWeight.w700, height: 1.55))
                else
                  for (var k = 0; k < l.lines.length; k++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.lines[k], style: Look.ui(19, weight: FontWeight.w700, height: 1.3)),
                        if (_under(k, l.lines[k], 15.5, Look.accent.withValues(alpha: 0.9)) case final Widget w) w,
                      ]),
                    ),
                const SizedBox(height: 18),
                if (l.source.isNotEmpty) Text('Lyrics: ${l.source}', style: Look.ui(12.5, color: Look.faint)),
              ]),
            ),
          ]);
        }
        return StreamBuilder<Duration>(
          stream: App.audio.position,
          builder: (context, pos) {
            final ms = (pos.data ?? Duration.zero).inMilliseconds + 250; // a quarter second early reads better
            final line = l.lineAt(ms);
            _follow(line, l);
            final list = ListView.builder(
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
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 260),
                        style: Look.ui(on ? 25 : 22,
                            weight: FontWeight.w800,
                            height: 1.25,
                            color: on ? Look.cream : (past ? Look.cream.withValues(alpha: 0.45) : Look.cream.withValues(alpha: 0.28))),
                        child: Text(l.lines[k]),
                      ),
                      if (_under(k, l.lines[k], on ? 17 : 15.5,
                          on ? Look.accent : Look.accent.withValues(alpha: past ? 0.4 : 0.3)) case final Widget w)
                        w,
                    ]),
                  ),
                );
              },
            );
            return Column(children: [_switch(l), Expanded(child: list)]);
          },
        );
      },
    );
  }
}
