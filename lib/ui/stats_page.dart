/// Your listening on the phone: minutes on the tape counter, top songs and artists, the hours you listen
/// at and your streak; and Rewind, Mixtape's own Wrapped, for this month so far, last month or the
/// year, told in cards you tap through and ending on a J-card to keep as a tape or share as a picture.
library;

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mixtape_native/mixtape_native.dart';

import '../app.dart';
import '../history.dart';
import '../look.dart';
import '../model.dart';
import '../store.dart';
import 'pages.dart';
import 'shell.dart';
import 'widgets.dart';

(DateTime, DateTime, String) _range(String period) {
  final now = DateTime.now();
  final end = now.add(const Duration(minutes: 1));
  return switch (period) {
    'week' => (DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1)), end, 'This week'),
    'month' => (DateTime(now.year, now.month), end, 'This month'),
    // DateTime counts a month 0 as the December before
    'last' => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month), 'Last month'),
    'year' => (DateTime(now.year), end, 'This year'),
    _ => (DateTime(2000), end, 'All time'),
  };
}

/// Last month, as the Rewind of it calls it: its name, and the year when it was another one.
String lastMonthName() {
  final now = DateTime.now();
  final m = DateTime(now.year, now.month - 1);
  return m.year == now.year ? _monthName(m.month) : '${_monthName(m.month)} ${m.year}';
}

/// Whether last month has enough music in it for a Rewind.
bool lastMonthHasMusic() {
  final (from, to, _) = _range('last');
  return App.history.between(from, to).plays.length >= 5;
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
            if (s.plays.isNotEmpty || lastMonthHasMusic())
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Row(children: [
                  Expanded(
                    child: _RewindButton(
                      title: '${_monthName(DateTime.now().month)} so far',
                      onTap: () => RewindPage.open(context, 'month'),
                    ),
                  ),
                  if (lastMonthHasMusic()) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RewindButton(title: lastMonthName(), onTap: () => RewindPage.open(context, 'last')),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RewindButton(
                      title: '${DateTime.now().year}',
                      onTap: () => RewindPage.open(context, 'year'),
                    ),
                  ),
                ]),
              ),
            if (s.plays.isNotEmpty) ...[
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

class _RewindButton extends StatelessWidget {
  const _RewindButton({required this.title, required this.onTap});

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.fast_rewind_rounded, color: Look.bg, size: 16),
                const SizedBox(width: 4),
                Text('REWIND', style: Look.cond(11.5, color: Look.bg, spacing: 1.6)),
              ]),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(title, maxLines: 1, style: Look.ui(15.5, weight: FontWeight.w800, color: Look.bg)),
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

// ---------------------------------------------------------------- Rewind

/// This month so far, last month or the year in cards: tap the right side for the next, the left for
/// the one before, hold to stop the clock. Each card moves on by itself after a few seconds, up to the
/// J-card at the end, which stays.
class RewindPage extends StatefulWidget {
  const RewindPage({super.key, required this.period});

  final String period;

  static Future<void> open(BuildContext context, String period) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => RewindPage(period: period)));

  @override
  State<RewindPage> createState() => _RewindPageState();
}

class _RewindPageState extends State<RewindPage> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _go(1);
    });
  int _card = 0;
  late final Stats _s;
  late final String _when;
  late final List<String> _new;
  final _jcard = GlobalKey();
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    final (from, to, _) = _range(widget.period);
    _s = App.history.between(from, to);
    _new = App.history.newArtists(from, to);
    _when = switch (widget.period) {
      'year' => '${DateTime.now().year}',
      'last' => lastMonthName(),
      _ => _monthName(DateTime.now().month),
    };
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
    final streak = s.longestStreak;
    final months = s.months;
    final busiest = months.reduce(max);
    return [
      _Card(colors: [Look.stripes[0], const Color(0xFF3B1D0E)], children: [
        Text('YOUR', style: Look.cond(22, color: Look.cream, spacing: 6)),
        FittedBox(fit: BoxFit.scaleDown, child: Text(_when, style: Look.hand(72, color: Look.cream))),
        Text(widget.period == 'month' ? 'so far, on Mixtape' : 'on Mixtape', style: Look.ui(22, weight: FontWeight.w800)),
        const SizedBox(height: 28),
        const SizedBox(width: 240, child: TapeArtPlain(title: 'rewind', playing: true, sticky: 'rewind!')),
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
      if (_new.isNotEmpty)
        _Card(colors: const [Color(0xFF8C4A1E), Look.bg], children: [
          Text(_new.length == 1 ? 'One artist was' : '${_new.length} artists were', style: Look.ui(22, weight: FontWeight.w800)),
          Text('new to you', style: Look.hand(54, color: Look.cream)),
          const SizedBox(height: 22),
          for (final name in _new.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(name, textAlign: TextAlign.center, style: Look.ui(19, weight: FontWeight.w700)),
            ),
          if (_new.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('and ${_new.length - 5} more', style: Look.ui(15, color: Look.cream.withValues(alpha: 0.75))),
            ),
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
      if (streak >= 2)
        _Card(colors: const [Color(0xFF9E2B25), Look.bg], children: [
          Text('Your longest streak', style: Look.ui(20, weight: FontWeight.w700)),
          const SizedBox(height: 16),
          Counter('$streak'.padLeft(2, '0'), height: 72, color: Look.cream),
          const SizedBox(height: 12),
          Text('days in a row', style: Look.hand(46, color: Look.cream)),
          const SizedBox(height: 12),
          Text(streak >= 7 ? 'Not one day without music.' : 'Music, day after day.',
              style: Look.ui(16, color: Look.cream.withValues(alpha: 0.8))),
        ]),
      if (widget.period == 'year' && months.where((m) => m > 0).length >= 2)
        _Card(colors: const [Color(0xFF2D4F7C), Look.bg], children: [
          Text('Your months', style: Look.ui(24, weight: FontWeight.w900)),
          const SizedBox(height: 22),
          SizedBox(
            height: 200,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var k = 0; k < 12; k++)
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      height: busiest == 0 ? 0 : 170 * months[k] / busiest,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: months[k] == busiest ? Look.stripes[0] : Look.cream.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_monthName(k + 1)[0], style: Look.ui(12.5, weight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          if (busiest > 0)
            Text('${_monthName(months.indexOf(busiest) + 1)} was the loudest: $busiest minutes.',
                textAlign: TextAlign.center, style: Look.ui(16, color: Look.cream.withValues(alpha: 0.85))),
        ]),
      _Card(colors: [Look.stripes[1], const Color(0xFF3B1D0E)], children: [
        RepaintBoundary(
          key: _jcard,
          child: JCard(
            title: _when,
            songs: [for (final x in songs.take(10)) x.$1],
            minutes: s.minutes,
            topArtist: artists.isEmpty ? '' : artists.first.$1,
            streak: streak,
          ),
        ),
        const SizedBox(height: 22),
        Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
          if (songs.isNotEmpty)
            FilledButton.icon(
              onPressed: () {
                final list = [for (final x in songs.take(30)) x.$1];
                final tape = App.library.newTape('Rewind $_when', songs: list);
                Navigator.of(context).pop();
                Shell.push(MixView(title: tape.shownName, blurb: 'your most played', songs: list, slot: 5));
              },
              icon: const Icon(Icons.queue_music_rounded),
              label: const Text('Make it a tape'),
            ),
          FilledButton.tonalIcon(
            onPressed: _sharing ? null : _share,
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share the card'),
          ),
        ]),
      ]),
    ];
  }

  /// The J-card as a picture, handed to the share sheet (save it, send it, post it).
  Future<void> _share() async {
    final box = _jcard.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return;
    setState(() => _sharing = true);
    _clock.stop();
    try {
      final image = await box.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return;
      final file = Store.the.file('rewind-${_when.replaceAll(' ', '-').toLowerCase()}.png');
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      final shared = await MixtapeNative.shareImage(file.path, text: 'My $_when on Mixtape');
      if (!shared && mounted) say(context, 'The picture is on the phone, in Mixtape\'s folder: ${file.path}');
    } on Object {
      if (mounted) say(context, "Couldn't make the picture this time.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _go(int step) {
    final n = _cards.length;
    final next = _card + step;
    if (next >= n) return; // the J-card stays until it's closed
    setState(() => _card = max(0, next));
    if (_card == n - 1) {
      _clock.value = 1; // the last card: its bar full, no clock running
    } else {
      _clock.forward(from: 0);
    }
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

/// A J-card, the paper in a cassette's case: the stripes, REWIND and the month or year by hand, the
/// top ten songs written down the inside, and the numbers along the bottom. Drawn on its own so it can
/// become a picture.
class JCard extends StatelessWidget {
  const JCard({super.key, required this.title, required this.songs, required this.minutes, required this.topArtist, required this.streak});

  final String title;
  final List<Track> songs;
  final int minutes;
  final String topArtist;
  final int streak;

  static const _paper = Color(0xFFF6EEDC);

  @override
  Widget build(BuildContext context) {
    final stripes = Look.stripes;
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // the spine, with the fold beside it
          Container(
            width: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE2CB),
              border: Border(right: BorderSide(color: Look.ink.withValues(alpha: 0.18))),
            ),
            child: RotatedBox(
              quarterTurns: 3,
              child: Center(
                child: Text('REWIND  ·  ${title.toUpperCase()}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.cond(12, color: Look.ink, spacing: 2.4)),
              ),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (k, h) in const [(0, 7.0), (1, 5.0), (2, 3.5)])
                Container(height: h, color: stripes[k % stripes.length]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 14, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('REWIND', style: Look.cond(13, color: Look.ink, spacing: 3)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(title, style: Look.hand(40, color: Look.ink)),
                  ),
                  Container(height: 1.2, color: Look.ink.withValues(alpha: 0.35), margin: const EdgeInsets.only(bottom: 8)),
                  for (var k = 0; k < songs.length; k++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 22, child: Text('${k + 1}', style: Look.hand(17, color: Look.ink.withValues(alpha: 0.6)))),
                        Expanded(
                          child: Text(
                            songs[k].artist.isEmpty ? songs[k].title : '${songs[k].title} - ${firstArtist(songs[k].artist)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Look.hand(17, color: Look.ink),
                          ),
                        ),
                      ]),
                    ),
                  if (songs.isEmpty) Text('a quiet one', style: Look.hand(20, color: Look.ink.withValues(alpha: 0.6))),
                ]),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 14, 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Look.ink.withValues(alpha: 0.18)))),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      [
                        '$minutes min',
                        if (topArtist.isNotEmpty) 'top: $topArtist',
                        if (streak >= 2) '$streak days in a row',
                      ].join('  ·  '),
                      maxLines: 2,
                      style: Look.ui(11.5, weight: FontWeight.w700, color: Look.ink.withValues(alpha: 0.8), height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('mixtape', style: Look.hand(18, color: stripes[0])),
                ]),
              ),
            ]),
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
