/// Home: moods to pick (YouTube Music's chips), shortcuts to what you play most (Spotify's grid), Quick
/// picks, your tapes, mixes made from what you play, songs to listen to again and YouTube Music's own
/// shelves.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import '../model.dart';
import '../music.dart';
import '../phone.dart';
import 'pages.dart';
import 'settings_page.dart';
import 'shell.dart';
import 'sign_in.dart';
import 'stats_page.dart';
import 'tape_page.dart';
import 'together_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeFeed? _feed;
  String _chip = '';
  List<Shelf> _mood = const [];
  bool _moodLoading = false;
  List<Track> _picks = const [];
  List<Track> _discover = const [];
  String _picksFor = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool fresh = false}) async {
    unawaited(_loadFeed());
    await _loadPicks(fresh: fresh);
  }

  Future<void> _loadFeed() async {
    try {
      final f = await Music.home();
      if (mounted) setState(() => _feed = f);
    } on Object {
      // offline: Home shows what's on the phone
    }
  }

  /// Quick picks: radio from what played lately and what you like, mixed, without repeats and at most
  /// two songs per artist. Discover: the ones of those you never played.
  Future<void> _loadPicks({bool fresh = false}) async {
    final lib = App.library;
    final seeds = <Track>[
      for (final t in [...lib.recent.take(6), ...lib.liked.reversed.take(6)])
        if (t.src == 'yt') t,
    ];
    final key = seeds.take(3).map((t) => t.id).join();
    if (seeds.isEmpty || (key == _picksFor && !fresh)) return;
    _picksFor = key;
    final pool = <Track>[];
    for (final s in seeds.take(3)) {
      try {
        pool.addAll((await Music.next(s.ref)).songs.skip(1));
      } on Object {
        continue;
      }
    }
    final rng = Random(DateTime.now().hour + DateTime.now().day * 24);
    pool.shuffle(rng);
    final known = {for (final t in lib.liked) t.id, for (final t in lib.recent) t.id};
    final seen = <String>{};
    final perArtist = <String, int>{};
    final picks = <Track>[], discover = <Track>[];
    for (final t in pool) {
      final a = t.artist.toLowerCase();
      if (lib.isHidden(t) || !seen.add(t.id) || (perArtist[a] ?? 0) >= 2) continue;
      perArtist[a] = (perArtist[a] ?? 0) + 1;
      if (picks.length < 20) picks.add(t);
      if (!known.contains(t.id) && discover.length < 30) discover.add(t);
    }
    if (mounted) {
      setState(() {
        _picks = picks;
        _discover = discover;
      });
    }
  }

  Future<void> _pickChip(String name, String params) async {
    if (_chip == name) {
      setState(() => _chip = '');
      return;
    }
    setState(() {
      _chip = name;
      _moodLoading = true;
      _mood = const [];
    });
    try {
      final f = await Music.home(params: params);
      if (mounted && _chip == name) setState(() => _mood = f.shelves);
    } on Object {
      if (mounted) say(context, "YouTube Music didn't answer. Check the internet connection.");
    } finally {
      if (mounted) setState(() => _moodLoading = false);
    }
  }

  static String _hello() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Still up?';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([App.library, App.downloads]),
      builder: (context, _) {
        final lib = App.library;
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadPicks());
        final tapes = lib.shownTapes.reversed.take(12).toList();
        final empty = tapes.isEmpty && lib.recent.isEmpty && lib.liked.isEmpty;
        final feed = _feed;
        return Scaffold(
          body: RefreshIndicator(
            color: Look.accent,
            backgroundColor: Look.raised,
            onRefresh: () => _load(fresh: true),
            child: CustomScrollView(slivers: [
              const _TopBar(),
              if (feed != null && feed.chips.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 50,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                      children: [
                        for (final (name, params) in feed.chips)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _Chip(name, on: _chip == name, onTap: () => _pickChip(name, params)),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_chip.isNotEmpty) ..._moodShelves() else ...[
                if (empty) const SliverToBoxAdapter(child: _Welcome()),
                if (!empty) SliverToBoxAdapter(child: _Shortcuts(hello: _hello())),
                if (!empty) const SliverToBoxAdapter(child: _BackgroundTip()),
                if (_picks.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionTitle('Quick picks', over: 'Start a radio from a song')),
                  SliverToBoxAdapter(child: _QuickPicks(_picks)),
                ],
                if (tapes.isNotEmpty || lib.liked.isNotEmpty) ...[
                  SliverToBoxAdapter(child: SectionTitle('Your tapes', onMore: () => Shell.goTo(3))),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 176,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          if (lib.liked.isNotEmpty) _LikedTile(onTap: () => Shell.push(const TapePage.liked())),
                          for (final t in tapes) TapeTile(tape: t, onTap: () => Shell.push(TapePage(tape: t))),
                        ],
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(child: _Mixes(discover: _discover)),
                if (lib.recent.length > 2) ...[
                  const SliverToBoxAdapter(child: SectionTitle('Listen again')),
                  SliverToBoxAdapter(child: _Again(lib.recent.take(16).toList())),
                ],
                if (feed != null)
                  for (final shelf in feed.shelves) ...[
                    SliverToBoxAdapter(child: SectionTitle(shelf.title, over: shelf.subtitle)),
                    SliverToBoxAdapter(child: CardRow(shelf.items)),
                  ],
              ],
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 20)),
            ]),
          ),
        );
      },
    );
  }

  List<Widget> _moodShelves() {
    if (_moodLoading) {
      return const [
        SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    return [
      for (final shelf in _mood) ...[
        SliverToBoxAdapter(child: SectionTitle(shelf.title, over: shelf.subtitle)),
        SliverToBoxAdapter(child: CardRow(shelf.items)),
      ],
    ];
  }
}

/// Once, on phones whose battery manager stops music in the background (Xiaomi, Huawei, Oppo, Vivo,
/// Samsung, ...): first Android's own battery saving, then the maker's switch, in its own words.
class _BackgroundTip extends StatelessWidget {
  const _BackgroundTip();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([PhoneInfo.the, App.settings]),
      builder: (context, _) {
        final p = PhoneInfo.the;
        if (!p.isStrict || App.settings.backgroundTipDone) return const SizedBox.shrink();
        final first = !p.batteryFree;
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Look.accent.withValues(alpha: 0.22), Look.side]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Look.accent.withValues(alpha: 0.45)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(first ? Icons.battery_alert_rounded : Icons.tune_rounded, color: Look.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(first ? 'Keep the music going' : 'One more switch on ${p.name} phones',
                      style: Look.ui(16, weight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                first
                    ? 'Your ${p.name} can stop the music a while after the screen goes off. '
                        'Let Mixtape keep playing?'
                    : p.tip,
                style: Look.ui(14, color: Look.cream.withValues(alpha: 0.85), height: 1.4),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: App.settings.setBackgroundTipDone,
                  child: Text(first ? 'Not now' : 'Done'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: first ? p.askBatteryFree : p.openMakerSettings,
                  child: Text(first ? 'Let it play' : 'Open settings'),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final s = App.account.session;
    return SliverAppBar(
      floating: true,
      backgroundColor: Look.bg,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 18,
      toolbarHeight: 60,
      title: Row(children: [
        const SizedBox(width: 34, child: TapeArtPlain(title: '')),
        const SizedBox(width: 10),
        Text('MIXTAPE', style: Look.cond(21, color: Look.cream, spacing: 3)),
      ]),
      actions: [
        IconButton(
          tooltip: 'Listen together',
          icon: const Icon(Icons.groups_outlined, color: Look.cream),
          onPressed: () => TogetherPage.open(context),
        ),
        IconButton(
          tooltip: 'Your listening',
          icon: const Icon(Icons.insights_rounded, color: Look.cream),
          onPressed: () => Shell.push(const StatsPage()),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Shell.push(const SettingsPage()),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Look.accent,
              child: s == null
                  ? const Icon(Icons.settings_rounded, size: 18, color: Look.bg)
                  : Text(s.display.isEmpty ? '?' : String.fromCharCode(s.display.runes.first).toUpperCase(),
                      style: Look.ui(15, weight: FontWeight.w800, color: Look.bg)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.on, required this.onTap});

  final String text;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? Look.cream : Look.raised,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(text, style: Look.ui(14, weight: FontWeight.w600, color: on ? Look.bg : Look.cream)),
        ),
      ),
    );
  }
}

/// The first time: what Mixtape is, and the two ways in.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final signedIn = App.account.signedIn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FractionallySizedBox(
          widthFactor: 0.82,
          child: NowPlayingBuilder(
            builder: (context, item, playing) => TapeArtPlain(title: 'my first mixtape', playing: playing, sticky: 'hi!'),
          ),
        ),
        const SizedBox(height: 22),
        Text('Your mixtapes, in your pocket.', style: Look.ui(22, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          signedIn
              ? 'Your tapes come over from your Mixtape Account in a moment. Meanwhile, search for a song or flick through Samples.'
              : 'Sign in with your Mixtape Account and your tapes and liked songs from the computer are here. Or search for a song, or flick through Samples.',
          style: Look.ui(15, color: Look.muted, height: 1.4),
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (!signedIn)
            FilledButton.icon(
              onPressed: () => SignInPage.open(context),
              icon: const Icon(Icons.person_rounded),
              label: const Text('Sign in'),
            ),
          OutlinedButton.icon(
            onPressed: () => Shell.goTo(2),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Search'),
          ),
          OutlinedButton.icon(
            onPressed: () => Shell.goTo(1),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Samples'),
          ),
        ]),
      ]),
    );
  }
}

/// Spotify's grid of shortcuts: Liked songs, the tapes and pages opened lately.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.hello});

  final String hello;

  @override
  Widget build(BuildContext context) {
    final lib = App.library;
    final tiles = <Widget>[
      if (lib.liked.isNotEmpty)
        _Shortcut(
          art: const _LikedSquare(),
          title: 'Liked songs',
          onTap: () => Shell.push(const TapePage.liked()),
        ),
    ];
    for (final o in lib.opened) {
      if (tiles.length >= 8) break;
      final kind = '${o['kind']}';
      final id = '${o['id']}';
      final title = '${o['title'] ?? ''}';
      if (kind == 'tape') {
        final tape = lib.tapes[id];
        if (tape == null) continue;
        tiles.add(_Shortcut(
          art: SizedBox(width: 56, child: Center(child: TapeArt(tape: tape, small: true))),
          title: tape.shownName,
          onTap: () => Shell.push(TapePage(tape: tape)),
        ));
      } else {
        tiles.add(_Shortcut(
          art: Pic('${o['art'] ?? ''}', size: 56, radius: 0, round: false, icon: kind == 'artist' ? Icons.person_rounded : null),
          title: title,
          onTap: () => Shell.push(kind == 'artist' ? ArtistView(id: id, name: title) : AlbumView(id: id, title: title)),
        ));
      }
    }
    for (final t in lib.shownTapes.reversed) {
      if (tiles.length >= 6) break;
      if (lib.opened.any((o) => o['kind'] == 'tape' && o['id'] == t.name)) continue;
      tiles.add(_Shortcut(
        art: SizedBox(width: 56, child: Center(child: TapeArt(tape: t, small: true))),
        title: t.shownName,
        onTap: () => Shell.push(TapePage(tape: t)),
      ));
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 12),
          child: Text(hello, style: Look.ui(24, weight: FontWeight.w800)),
        ),
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in tiles) SizedBox(width: w, child: t),
          ]);
        }),
      ]),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.art, required this.title, required this.onTap});

  final Widget art;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Look.raised,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            SizedBox(width: 56, height: 56, child: ColoredBox(color: Look.side, child: Center(child: art))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(13.5, weight: FontWeight.w700, height: 1.15)),
            ),
            const SizedBox(width: 6),
          ]),
        ),
      ),
    );
  }
}

class _LikedSquare extends StatelessWidget {
  const _LikedSquare();

  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Look.stripes[0], Look.stripes[1], Look.stripes[2]],
          ),
        ),
        child: const Icon(Icons.favorite_rounded, color: Look.bg),
      );
}

/// YouTube Music's Quick picks: four songs to a column, columns side by side, a flick a column.
class _QuickPicks extends StatefulWidget {
  const _QuickPicks(this.songs);

  final List<Track> songs;

  @override
  State<_QuickPicks> createState() => _QuickPicksState();
}

class _QuickPicksState extends State<_QuickPicks> {
  final _pages = PageController(viewportFraction: 0.88);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs;
    final columns = (songs.length / 4).ceil();
    return SizedBox(
      height: 4 * 62.0 * MediaQuery.textScalerOf(context).scale(1),
      child: NowPlayingBuilder(
        builder: (context, item, playing) => PageView.builder(
          controller: _pages,
          padEnds: false,
          itemCount: columns,
          itemBuilder: (context, c) => Column(children: [
            for (var k = c * 4; k < min(songs.length, c * 4 + 4); k++)
              Expanded(
                child: SongRow(
                  track: songs[k],
                  current: item?.id == songs[k].id,
                  playing: playing,
                  onTap: () => App.audio.playSongs([songs[k]], from: '${songs[k].title} radio'),
                ),
              ),
            for (var k = min(songs.length, c * 4 + 4); k < c * 4 + 4; k++) const Spacer(),
          ]),
        ),
      ),
    );
  }
}

class _LikedTile extends StatelessWidget {
  const _LikedTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final liked = App.library.liked;
    return SizedBox(
      width: 168,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const LikedArt(),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.favorite_rounded, size: 15, color: Look.accent),
              const SizedBox(width: 5),
              Text('Liked songs', style: Look.ui(14.5, weight: FontWeight.w600)),
            ]),
            Text(count(liked.length), style: Look.ui(12.5, color: Look.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Tapes Mixtape puts together from what you play: on repeat, new to you, your daily mix and a time
/// capsule of songs from a while ago.
class _Mixes extends StatelessWidget {
  const _Mixes({required this.discover});

  final List<Track> discover;

  @override
  Widget build(BuildContext context) {
    final lib = App.library;
    final history = App.history;
    final repeat = history.onRepeat();
    final now = DateTime.now();
    final old = history.between(now.subtract(const Duration(days: 365)), now.subtract(const Duration(days: 45)));
    final capsule = [
      for (final (t, n) in old.songs)
        if (n >= 2) t,
    ].take(30).toList();
    final day = Random(now.year * 400 + now.month * 31 + now.day);
    final daily = [...lib.liked.reversed.take(60)]..shuffle(day);
    final mix = <Track>[...daily.take(15), ...discover.take(10)]..shuffle(day);
    final mixes = <(String, String, List<Track>, int, Map<String, Object?>)>[
      if (mix.length >= 5) ('Daily mix', 'what you like, and a few new ones', mix, 1, const {'shell': 'clear', 'stripes': 'fade'}),
      if (repeat.length >= 5) ('On repeat', 'the songs you keep coming back to', repeat, 3, const {'shell': 'red', 'pen': 'marker'}),
      if (discover.length >= 5) ('Discover', 'new to you, close to what you like', discover, 4, const {'shell': 'blue', 'stripes': 'band'}),
      if (capsule.length >= 5) ('Time capsule', 'what you played a while ago', capsule, 6, const {'shell': 'white', 'pen': 'type'}),
    ];
    if (mixes.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Mixed for you', over: 'Made from your listening'),
      SizedBox(
        height: 190,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final (title, blurb, songs, slot, design) in mixes)
              SizedBox(
                width: 168,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Shell.push(MixView(title: title, blurb: blurb, songs: songs, slot: slot, design: design)),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TapeArtPlain(title: title, slot: slot, design: design, sticky: '${songs.length} songs'),
                      const SizedBox(height: 8),
                      Text(title, style: Look.ui(14.5, weight: FontWeight.w600)),
                      Text(blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(12.5, color: Look.muted, height: 1.2)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}

/// Songs played lately, as covers to tap.
class _Again extends StatelessWidget {
  const _Again(this.songs);

  final List<Track> songs;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 140 + 58 * scale,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: songs.length,
        itemBuilder: (context, k) {
          final t = songs[k];
          return SizedBox(
            width: 140,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => App.audio.playSongs(songs, start: k, from: 'Listen again'),
              onLongPress: () => songMenu(context, t),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Cover(t, size: 130, radius: 8),
                  const SizedBox(height: 8),
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(14, weight: FontWeight.w600)),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(12.5, color: Look.muted)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
