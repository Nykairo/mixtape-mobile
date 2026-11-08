/// Home: what played last, your tapes, your liked songs and songs like the ones you played lately.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../audio.dart';
import '../look.dart';
import '../model.dart';
import 'library_page.dart';
import 'settings_page.dart';
import 'shell.dart';
import 'sign_in.dart';
import 'tape_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Track> _like = const [];
  String _likeOf = '';
  bool _asked = false;

  /// Songs like the last one played: the songs YouTube lists next to it.
  Future<void> _more() async {
    Track? last;
    for (final t in App.library.recent) {
      if (t.src == 'yt') {
        last = t;
        break;
      }
    }
    if (last == null || last.id == _likeOf || _asked) return;
    _asked = true;
    try {
      await Links.get(last.ref);
      final have = {for (final t in App.library.recent) t.id};
      final like = [
        for (final t in Links.related(last.ref))
          if (!have.contains(t.id)) t,
      ].take(12).toList();
      if (mounted) {
        setState(() {
          _like = like;
          _likeOf = last.id;
        });
      }
    } on Object {
      // offline, or YouTube busy: the part just doesn't show
    } finally {
      _asked = false;
    }
  }

  static String _hello() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Still up';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.library,
      builder: (context, _) {
        final lib = App.library;
        WidgetsBinding.instance.addPostFrameCallback((_) => _more());
        final tapes = lib.shownTapes.reversed.take(12).toList();
        final recent = lib.recent.take(8).toList();
        final name = App.account.session?.display ?? '';
        final empty = tapes.isEmpty && recent.isEmpty && lib.liked.isEmpty;
        return Scaffold(
          body: CustomScrollView(slivers: [
            SliverAppBar(
              floating: true,
              backgroundColor: Look.bg,
              surfaceTintColor: Colors.transparent,
              titleSpacing: 20,
              toolbarHeight: 72,
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_hello().toUpperCase(), style: Look.cond(13, spacing: 2.4)),
                Text(name.isEmpty ? 'Mixtape' : name, style: Look.ui(26, weight: FontWeight.w800)),
              ]),
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.tune_rounded, color: Look.muted),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
                ),
                const SizedBox(width: 6),
              ],
            ),
            if (empty) const SliverToBoxAdapter(child: _Welcome()),
            if (recent.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionTitle('Pick up where you left off')),
              SliverToBoxAdapter(child: _LastPlayed(track: recent.first)),
            ],
            if (tapes.isNotEmpty || lib.liked.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionTitle('Your tapes',
                    trailing: TextButton(onPressed: () => Shell.goTo(context, 2), child: const Text('See all'))),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 176,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      if (lib.liked.isNotEmpty)
                        LikedTile(onTap: () => Navigator.of(context).push(TapePage.liked())),
                      for (final t in tapes)
                        TapeTile(tape: t, onTap: () => Navigator.of(context).push(TapePage.of(t))),
                    ],
                  ),
                ),
              ),
            ],
            if (recent.length > 1) ...[
              const SliverToBoxAdapter(child: SectionTitle('Played lately')),
              SliverList.builder(
                itemCount: recent.length,
                itemBuilder: (context, k) => NowPlayingBuilder(
                  builder: (context, item, playing) => SongRow(
                    track: recent[k],
                    current: item?.id == recent[k].id,
                    playing: playing,
                    onTap: () => App.audio.playSongs(lib.recent, start: k, from: 'Played lately'),
                  ),
                ),
              ),
            ],
            if (_like.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionTitle('More like what you played')),
              SliverList.builder(
                itemCount: _like.length,
                itemBuilder: (context, k) => NowPlayingBuilder(
                  builder: (context, item, playing) => SongRow(
                    track: _like[k],
                    current: item?.id == _like[k].id,
                    playing: playing,
                    onTap: () => App.audio.playSongs(_like, start: k, from: 'More like what you played'),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        );
      },
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
        const FractionallySizedBox(
          widthFactor: 0.82,
          child: _BlankTape(),
        ),
        const SizedBox(height: 22),
        Text('Your mixtapes, in your pocket.', style: Look.ui(22, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          signedIn
              ? 'Your tapes come over from your Mixtape Account in a moment. Meanwhile, search for a song.'
              : 'Sign in with your Mixtape Account and your tapes and liked songs from the computer are here. Or just search for a song.',
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
            onPressed: () => Shell.goTo(context, 1),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Search'),
          ),
        ]),
      ]),
    );
  }
}

class _BlankTape extends StatelessWidget {
  const _BlankTape();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
        child: _PlainCassette(),
      );
}

class _PlainCassette extends StatelessWidget {
  const _PlainCassette();

  @override
  Widget build(BuildContext context) {
    return NowPlayingBuilder(
      builder: (context, item, playing) => TapeArtPlain(title: 'my first mixtape', playing: playing),
    );
  }
}

/// The song that played last, big, with a button to carry on.
class _LastPlayed extends StatelessWidget {
  const _LastPlayed({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return NowPlayingBuilder(builder: (context, item, playing) {
      final on = item?.id == track.id;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: Look.side,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (on) {
                playing ? App.audio.pause() : App.audio.play();
              } else {
                App.audio.playSongs(App.library.recent, from: 'Played lately');
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Cover(track, size: 72, radius: 8),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(16.5, weight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13.5, color: Look.muted)),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Look.accent, shape: BoxShape.circle),
                  child: Icon(on && playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Look.bg, size: 28),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}
