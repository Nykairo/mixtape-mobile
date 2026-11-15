/// Your listening on the phone: minutes on the tape counter, top songs and artists, the hours you listen
/// at and your streak; and a Wrapped for the month or the year, told in cards you tap through.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../history.dart';
import '../look.dart';
import 'pages.dart';
import 'shell.dart';
import 'widgets.dart';

(DateTime, DateTime, String) _range(String period) {
  final now = DateTime.now();
  final end = now.add(const Duration(minutes: 1));
  return switch (period) {
    'week' => (DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1)), end, 'This week'),
    'month' => (DateTime(now.year, now.month), end, 'This month'),
    'year' => (DateTime(now.year), end, 'This year'),
    _ => (DateTime(2000), end, 'All time'),
  };
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.history,
      builder: (context, _) {
        final (from, to, name) = _range(_period);
        final s = App.history.between(from, to);
        final songs = s.songs;
        final artists = s.artists;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Look.bg,
            surfaceTintColor: Colors.transparent,
            title: Text('Your listening', style: Look.ui(19, weight: FontWeight.w800)),
          ),
          body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24), children: [
            // the four spans side by side, the words shrinking a little on the narrowest phones
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 4, 11, 6),
              child: Row(children: [
                for (final (k, n) in const [('week', 'This week'), ('month', 'This month'), ('year', 'This year'), ('all', 'All time')])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Material(
                        color: _period == k ? Look.cream : Look.raised,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => setState(() => _period = k),
                          child: SizedBox(
                            height: 36,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(n,
                                      style: Look.ui(13.5,
                                          weight: FontWeight.w600, color: _period == k ? Look.bg : Look.cream)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            _Totals(s: s, streak: App.history.streak),
            if (s.plays.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Row(children: [
                  Expanded(
                    child: _WrappedButton(
                      title: _monthName(DateTime.now().month),
                      onTap: () => WrappedPage.open(context, 'month'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _WrappedButton(
                      title: '${DateTime.now().year}',
                      onTap: () => WrappedPage.open(context, 'year'),
                    ),
                  ),
                ]),
              ),
              SectionTitle('Top songs', over: name),
              for (var k = 0; k < min(10, songs.length); k++)
                NowPlayingBuilder(
                  builder: (context, item, playing) => Row(children: [
                    SizedBox(
                      width: 36,
                      child: Text('${k + 1}', textAlign: TextAlign.right, style: Look.cond(18, color: k < 3 ? Look.accent : Look.faint)),
                    ),
                    Expanded(
                      child: SongRow(
                        track: songs[k].$1,
                        current: item?.id == songs[k].$1.id,
                        playing: playing,
                        onTap: () => App.audio.playSongs([for (final x in songs.take(30)) x.$1], start: k, from: 'Your top songs'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text('${songs[k].$2}×', style: Look.ui(13, color: Look.muted)),
                    ),
                  ]),
                ),
              const SectionTitle('Top artists'),
              for (var k = 0; k < min(8, artists.length); k++)
                _ArtistBar(name: artists[k].$1, minutes: artists[k].$2, most: max(1, artists.first.$2), place: k + 1),
              const SectionTitle('When you listen', over: 'Minutes in each hour of the day'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(height: 120, child: CustomPaint(painter: _Hours(s.hours, Look.accent))),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Row(children: [
                  for (final h in const ['0', '6', '12', '18', '24']) ...[
                    Text(h, style: Look.ui(11.5, color: Look.faint)),
                    if (h != '24') const Spacer(),
                  ],
                ]),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text('Nothing played ${name.toLowerCase()} yet. Songs count once they played for half a minute.',
                    textAlign: TextAlign.center, style: Look.ui(15, color: Look.muted, height: 1.4)),
              ),
          ]),
        );
      },
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.s, required this.streak});

  final Stats s;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Look.side,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Look.edge),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('MINUTES LISTENED', style: Look.cond(12.5, spacing: 2)),
          const SizedBox(height: 10),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: s.minutes),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Counter('$v'.padLeft(4, '0'), height: 44),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _Fact('${s.plays.length}', 'plays'),
            _Fact('${s.distinctSongs}', 'songs'),
            _Fact('${s.distinctArtists}', 'artists'),
            _Fact('$streak', streak == 1 ? 'day in a row' : 'days in a row'),
          ]),
        ]),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: Look.ui(20, weight: FontWeight.w800)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(12, color: Look.muted)),
        ]),
      );
}

class _ArtistBar extends StatelessWidget {
  const _ArtistBar({required this.name, required this.minutes, required this.most, required this.place});

  final String name;
  final int minutes;
  final int most;
  final int place;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Shell.push(SearchResultsView(query: name, filter: 'artists')),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(children: [
          SizedBox(width: 22, child: Text('$place', style: Look.cond(16, color: place <= 3 ? Look.accent : Look.faint))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15, weight: FontWeight.w600))),
                Text('$minutes min', style: Look.ui(12.5, color: Look.muted)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: minutes / most,
                  minHeight: 5,
                  backgroundColor: Look.raised,
                  color: Look.stripes[(place - 1) % 3],
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Hours extends CustomPainter {
  _Hours(this.hours, this.color);

  final List<int> hours;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final most = max(1, hours.reduce(max));
    final w = size.width / 24;
    final p = Paint()..color = color;
    final faint = Paint()..color = color.withValues(alpha: 0.14);
    for (var h = 0; h < 24; h++) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(h * w + w * 0.18, 0, w * 0.64, size.height), const Radius.circular(3));
      canvas.drawRRect(r, faint);
      final bar = size.height * hours[h] / most;
      if (bar > 0) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(h * w + w * 0.18, size.height - bar, w * 0.64, bar), const Radius.circular(3)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Hours old) => old.hours != hours || old.color != color;
}

class _WrappedButton extends StatelessWidget {
  const _WrappedButton({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Look.stripes[0], Look.stripes[1]])),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded, color: Look.bg),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('WRAPPED', style: Look.cond(11.5, color: Look.bg, spacing: 1.6)),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(16, weight: FontWeight.w800, color: Look.bg)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

String _monthName(int m) =>
    const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][m - 1];

// ---------------------------------------------------------------- Wrapped

/// The month or the year in cards: tap the right side for the next, the left for the one before, hold
/// to stop the clock. Each card moves on by itself after a few seconds.
class WrappedPage extends StatefulWidget {
  const WrappedPage({super.key, required this.period});

  final String period;

  static Future<void> open(BuildContext context, String period) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => WrappedPage(period: period)));

  @override
  State<WrappedPage> createState() => _WrappedPageState();
}

class _WrappedPageState extends State<WrappedPage> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _go(1);
    });
  int _card = 0;
  late final Stats _s;
  late final String _when;

  @override
  void initState() {
    super.initState();
    final (from, to, _) = _range(widget.period);
    _s = App.history.between(from, to);
    _when = widget.period == 'year' ? '${DateTime.now().year}' : _monthName(DateTime.now().month);
    _clock.forward();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  List<Widget> get _cards {
    final s = _s;
    final songs = s.songs;
    final artists = s.artists;
    final peak = s.peakHour;
    final (owl, owlWords) = peak < 0
        ? ('', '')
        : peak >= 22 || peak < 4
            ? ('Night owl', 'Most of your music played after ten at night.')
            : peak < 10
                ? ('Early riser', 'You start the day with music: most of it played before ten.')
                : peak < 17
                    ? ('Daytime listener', 'Your music keeps you company through the day.')
                    : ('Evening listener', 'Your music comes out after work.');
    return [
      _Card(colors: [Look.stripes[0], const Color(0xFF3B1D0E)], children: [
        Text('YOUR', style: Look.cond(22, color: Look.cream, spacing: 6)),
        Text(_when, style: Look.hand(72, color: Look.cream)),
        Text('on Mixtape', style: Look.ui(22, weight: FontWeight.w800)),
        const SizedBox(height: 28),
        const SizedBox(width: 240, child: TapeArtPlain(title: 'wrapped', playing: true, sticky: 'rewind!')),
      ]),
      _Card(colors: const [Color(0xFF25428E), Look.bg], children: [
        Text('You listened for', style: Look.ui(22, weight: FontWeight.w700)),
        const SizedBox(height: 16),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: s.minutes),
          duration: const Duration(milliseconds: 1800),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Counter('$v'.padLeft(4, '0'), height: 72, color: Look.cream),
        ),
        const SizedBox(height: 12),
        Text('minutes', style: Look.ui(26, weight: FontWeight.w900)),
        const SizedBox(height: 18),
        Text(s.minutes >= 60 ? "That's ${(s.minutes / 60).toStringAsFixed(1)} hours of tape." : 'Every minute counts.',
            style: Look.ui(16, color: Look.cream.withValues(alpha: 0.75))),
      ]),
      if (artists.isNotEmpty)
        _Card(colors: const [Color(0xFF7A3B62), Look.bg], children: [
          Text('Your top artist', style: Look.ui(20, weight: FontWeight.w700)),
          const SizedBox(height: 18),
          Text(artists.first.$1, textAlign: TextAlign.center, style: Look.ui(44, weight: FontWeight.w900, height: 1.05)),
          const SizedBox(height: 12),
          Text('${artists.first.$2} minutes together', style: Look.ui(17, color: Look.cream.withValues(alpha: 0.8))),
          const SizedBox(height: 26),
          for (var k = 1; k < min(5, artists.length); k++)
            Text('${k + 1}.  ${artists[k].$1}', style: Look.ui(17, weight: FontWeight.w600)),
        ]),
      if (songs.isNotEmpty)
        _Card(colors: const [Color(0xFF1F6B52), Look.bg], children: [
          Text('Your song', style: Look.ui(20, weight: FontWeight.w700)),
          const SizedBox(height: 18),
          Cover(songs.first.$1, size: 200, radius: 12),
          const SizedBox(height: 18),
          Text(songs.first.$1.title, textAlign: TextAlign.center, maxLines: 2, style: Look.ui(28, weight: FontWeight.w900)),
          Text(songs.first.$1.artist, style: Look.ui(17, color: Look.cream.withValues(alpha: 0.8))),
          const SizedBox(height: 10),
          Text('played ${songs.first.$2} times', style: Look.hand(28, color: Look.cream)),
        ]),
      if (songs.length >= 3)
        _Card(colors: const [Color(0xFF5A3C8F), Look.bg], children: [
          Text('Your top songs', style: Look.ui(24, weight: FontWeight.w900)),
          const SizedBox(height: 20),
          for (var k = 0; k < min(5, songs.length); k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 30, child: Text('${k + 1}', style: Look.cond(24, color: Look.cream))),
                Cover(songs[k].$1, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(songs[k].$1.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(16, weight: FontWeight.w700)),
                    Text(songs[k].$1.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.cream.withValues(alpha: 0.7))),
                  ]),
                ),
              ]),
            ),
        ]),
      if (owl.isNotEmpty)
        _Card(colors: const [Color(0xFF2A2733), Look.bg], children: [
          Icon(peak >= 22 || peak < 4 ? Icons.nightlight_round : Icons.wb_sunny_rounded, size: 64, color: Look.stripes[1]),
          const SizedBox(height: 18),
          Text("You're a", style: Look.ui(20, weight: FontWeight.w700)),
          Text(owl, style: Look.hand(54, color: Look.cream)),
          const SizedBox(height: 12),
          Text(owlWords, textAlign: TextAlign.center, style: Look.ui(16, color: Look.cream.withValues(alpha: 0.8), height: 1.4)),
        ]),
      _Card(colors: [Look.stripes[1], const Color(0xFF3B1D0E)], children: [
        Text('That was $_when.', style: Look.ui(28, weight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text('${s.distinctSongs} songs, ${s.distinctArtists} artists, ${s.days} days of music.',
            textAlign: TextAlign.center, style: Look.ui(16, color: Look.cream.withValues(alpha: 0.85))),
        const SizedBox(height: 26),
        if (songs.isNotEmpty)
          FilledButton.icon(
            onPressed: () {
              final list = [for (final x in songs.take(30)) x.$1];
              Navigator.of(context).pop();
              Shell.push(MixView(title: 'Wrapped $_when', blurb: 'your most played', songs: list, slot: 5));
            },
            icon: const Icon(Icons.queue_music_rounded),
            label: const Text('Your top songs as a tape'),
          ),
      ]),
    ];
  }

  void _go(int step) {
    final n = _cards.length;
    final next = _card + step;
    if (next >= n) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _card = max(0, next));
    _clock.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) => _go(d.globalPosition.dx > MediaQuery.sizeOf(context).width / 3 ? 1 : -1),
        onLongPressStart: (_) => _clock.stop(),
        onLongPressEnd: (_) => _clock.forward(),
        child: Stack(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: KeyedSubtree(key: ValueKey(_card), child: cards[min(_card, cards.length - 1)]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Row(children: [
                for (var k = 0; k < cards.length; k++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedBuilder(
                        animation: _clock,
                        builder: (context, _) => LinearProgressIndicator(
                          value: k < _card ? 1 : (k == _card ? _clock.value : 0),
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                IconButton(
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

class _Card extends StatelessWidget {
  const _Card({required this.colors, required this.children});

  final List<Color> colors;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: SafeArea(
        child: Center(
          // on a tablet or an unfolded foldable the card is laid out at a phone's width and drawn bigger,
          // so it fills the screen the way it fills a phone's
          child: MediaQuery.sizeOf(context).shortestSide >= 520
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(28, 60, 28, 40),
                  child: FittedBox(
                    child: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: children)),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 60, 28, 40),
                  child: Column(mainAxisSize: MainAxisSize.min, children: children),
                ),
        ),
      ),
    );
  }
}
