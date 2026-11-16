/// The pages YouTube Music's things open into: an artist, an album or a playlist, a mood, a mix Mixtape
/// made, and the results of a search on a page of their own.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import '../model.dart';
import '../music.dart';
import 'search.dart';
import 'shell.dart';
import 'tint.dart';
import 'widgets.dart';

/// A page whose top wears a color (an album's cover color, a mood's own) fading into the deck.
class ColorTop extends StatelessWidget {
  const ColorTop({super.key, required this.color, required this.child, this.height = 360});

  final Color? color;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    // as tall as what's in it ([height] is how far the color reaches at most), so no empty band opens
    // up under it on a narrow phone
    return Stack(children: [
      Positioned.fill(
        child: LayoutBuilder(
          builder: (context, room) => Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: min(room.maxHeight, height),
              decoration: BoxDecoration(gradient: fadeFrom(color ?? Look.side, strength: color == null ? 0.4 : 0.85)),
            ),
          ),
        ),
      ),
      child,
    ]);
  }
}

/// Play (big), shuffle, save on the phone and save as a tape, under a list's title.
class PlayRow extends StatelessWidget {
  const PlayRow({super.key, required this.songs, required this.from, this.name = '', this.extra = const []});

  final List<Track> songs;
  final String from;
  final String name;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final can = songs.any((t) => t.playable);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 16, 6),
      child: Row(children: [
        DownloadButton(songs: songs, name: name),
        IconButton(
          tooltip: 'Save as a tape',
          onPressed: songs.isEmpty
              ? null
              : () async {
                  final title = await askText(context, title: 'Save as a tape', start: name, action: 'Save');
                  if (title == null || !context.mounted) return;
                  final tape = App.library.newTape(title, songs: songs);
                  say(context, 'Saved as ${tape.shownName}');
                },
          icon: const Icon(Icons.library_add_outlined, color: Look.cream),
        ),
        ...extra,
        const Spacer(),
        IconButton(
          tooltip: 'Shuffle',
          iconSize: 28,
          onPressed: can ? () => App.audio.playSongs(songs, shuffle: true, from: from) : null,
          icon: const Icon(Icons.shuffle_rounded, color: Look.cream),
        ),
        const SizedBox(width: 6),
        Material(
          color: Look.accent,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: can ? () => App.audio.playSongs(songs, from: from) : null,
            child: const SizedBox.square(dimension: 56, child: Icon(Icons.play_arrow_rounded, size: 34, color: Look.bg)),
          ),
        ),
      ]),
    );
  }
}

Widget _loading() => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));

Widget _failed(String text, VoidCallback again) => Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Text(text, textAlign: TextAlign.center, style: Look.ui(15, color: Look.muted, height: 1.4)),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: again, child: const Text('Try again')),
      ]),
    );

const _offline = "YouTube Music didn't answer. Check the internet connection.";

// ---------------------------------------------------------------- an artist

class ArtistView extends StatefulWidget {
  const ArtistView({super.key, required this.id, this.name = ''});

  final String id;
  final String name;

  @override
  State<ArtistView> createState() => _ArtistViewState();
}

class _ArtistViewState extends State<ArtistView> {
  late Future<ArtistPage> _page = Music.artist(widget.id);
  bool _about = false;

  Future<void> _shuffle(ArtistPage a) async {
    var songs = a.songs;
    if (a.allSongs.isNotEmpty) {
      try {
        songs = (await Music.list(a.allSongs)).songs;
      } on Object {
        songs = a.songs;
      }
    }
    await App.audio.playSongs(songs, shuffle: true, from: a.name);
  }

  Future<void> _radio(ArtistPage a) async {
    try {
      final seed = a.radioSeed.isNotEmpty ? a.radioSeed : (a.songs.isEmpty ? '' : a.songs.first.ref);
      if (seed.isEmpty) return;
      final next = await Music.next(seed, playlist: a.radio);
      await App.audio.playSongs(next.songs, from: '${a.name} radio');
    } on Object {
      if (mounted) say(context, _offline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: FutureBuilder<ArtistPage>(
        future: _page,
        builder: (context, snap) {
          final a = snap.data;
          if (a == null) {
            return Scaffold(
              appBar: AppBar(backgroundColor: Look.bg, title: Text(widget.name)),
              body: snap.hasError ? _failed(_offline, () => setState(() => _page = Music.artist(widget.id))) : _loading(),
            );
          }
          return CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              stretch: true,
              expandedHeight: min(width * 0.75, 340),
              backgroundColor: Look.bg,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(start: 54, bottom: 14, end: 16),
                title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(22, weight: FontWeight.w900)),
                background: Stack(fit: StackFit.expand, children: [
                  if (a.art.isNotEmpty) Image.network(a.art, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC191410), Look.bg],
                        stops: [0.35, 0.8, 1],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (a.audience.isNotEmpty) Text(a.audience, style: Look.ui(13.5, color: Look.muted)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Pill(Icons.shuffle_rounded, 'Shuffle', () => _shuffle(a), on: true),
                    Pill(Icons.radio_rounded, 'Radio', () => _radio(a)),
                    if (a.songs.isNotEmpty) Pill(Icons.ios_share_rounded, 'Share', () => shareSong(context, a.songs.first)),
                  ]),
                ]),
              ),
            ),
            if (a.songs.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionTitle('Top songs',
                    onMore: a.allSongs.isEmpty ? null : () => Shell.push(AlbumView(id: a.allSongs, title: '${a.name}: songs'))),
              ),
              SliverList.builder(
                itemCount: a.songs.length,
                itemBuilder: (context, k) => NowPlayingBuilder(
                  builder: (context, item, playing) => SongRow(
                    track: a.songs[k],
                    current: item?.id == a.songs[k].id,
                    playing: playing,
                    onTap: () => App.audio.playSongs(a.songs, start: k, from: a.name),
                  ),
                ),
              ),
            ],
            for (final shelf in a.shelves) ...[
              SliverToBoxAdapter(
                child: SectionTitle(shelf.title,
                    onMore: shelf.more.isEmpty ? null : () => Shell.push(AlbumView(id: shelf.more, title: shelf.title))),
              ),
              SliverToBoxAdapter(child: CardRow(shelf.items, width: shelf.items.first.kind == Kind.artist ? 130 : 150)),
            ],
            if (a.about.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 22, 14, 0),
                  child: Material(
                    color: Look.raised,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _about = !_about),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('About', style: Look.ui(18, weight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(a.about,
                              maxLines: _about ? 60 : 4,
                              overflow: TextOverflow.ellipsis,
                              style: Look.ui(14, color: Look.muted, height: 1.45)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- an album or a playlist

class AlbumView extends StatefulWidget {
  const AlbumView({super.key, required this.id, this.title = ''});

  final String id;
  final String title;

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> {
  ListPage? _page;
  Object? _error;
  Color? _color;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await Music.list(widget.id);
      if (!mounted) return;
      setState(() => _page = p);
      final c = await Tint.ofUrl(p.art);
      if (mounted) setState(() => _color = c);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadMore() async {
    final p = _page;
    if (p == null || p.more.isEmpty || _more) return;
    _more = true;
    try {
      final next = await Music.more(p);
      if (mounted) setState(() => _page = next);
    } on Object {
      // the list just ends here for now
    } finally {
      _more = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Look.bg, title: Text(widget.title)),
        body: _error != null ? _failed(_offline, _load) : _loading(),
      );
    }
    final album = p.kind == Kind.album;
    final side = min(MediaQuery.sizeOf(context).width * 0.62, 260.0);
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _loadMore();
          return false;
        },
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Color.lerp(Look.bg, _color ?? Look.side, 0.5),
            surfaceTintColor: Colors.transparent,
            title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(17, weight: FontWeight.w700)),
          ),
          SliverToBoxAdapter(
            child: ColorTop(
              color: _color,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 14))],
                      ),
                      child: Pic(p.art, size: side, radius: 8),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(p.title, style: Look.ui(24, weight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 6),
                  if (p.artist.isNotEmpty)
                    InkWell(
                      onTap: p.artistId.isEmpty ? null : () => Shell.push(ArtistView(id: p.artistId, name: p.artist)),
                      child: Text(p.artist, style: Look.ui(15, weight: FontWeight.w700)),
                    ),
                  Text([p.subtitle, p.second].where((s) => s.isNotEmpty).join('  ·  '),
                      style: Look.ui(13, color: Look.muted)),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(child: PlayRow(songs: p.songs, from: p.title, name: p.title)),
          SliverList.builder(
            itemCount: p.songs.length,
            itemBuilder: (context, k) => NowPlayingBuilder(
              builder: (context, item, playing) => SongRow(
                track: p.songs[k],
                number: album ? k + 1 : null,
                current: item?.id == p.songs[k].id,
                playing: playing,
                onTap: () => App.audio.playSongs(p.songs, start: k, from: p.title),
              ),
            ),
          ),
          if (p.more.isNotEmpty) SliverToBoxAdapter(child: _loading()),
          if (p.about.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Text(p.about, style: Look.ui(13.5, color: Look.muted, height: 1.45)),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- a mix Mixtape made

class MixView extends StatelessWidget {
  const MixView({
    super.key,
    required this.title,
    required this.songs,
    this.blurb = '',
    this.slot = 0,
    this.design,
  });

  final String title;
  final String blurb;
  final List<Track> songs;
  final int slot;
  final Map<String, Object?>? design;

  @override
  Widget build(BuildContext context) {
    final seconds = songs.fold(0, (s, t) => s + t.dur);
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Look.bg,
          surfaceTintColor: Colors.transparent,
          title: Text(title, style: Look.ui(17, weight: FontWeight.w700)),
        ),
        SliverToBoxAdapter(
          child: ColorTop(
            color: paperColor(slot),
            height: 300,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NowPlayingBuilder(
                  builder: (context, item, playing) => TapeArtPlain(
                    title: title,
                    slot: slot,
                    design: design,
                    sticky: blurb.split(' ').take(2).join(' '),
                    playing: playing && App.audio.from == title,
                  ),
                ),
                const SizedBox(height: 16),
                Text(title, style: Look.hand(36, color: Look.cream)),
                Text('${count(songs.length)}  ·  ${tapeFor(seconds)}${blurb.isEmpty ? '' : '  ·  $blurb'}',
                    style: Look.ui(13, color: Look.muted)),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(child: PlayRow(songs: songs, from: title, name: title)),
        SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, k) => NowPlayingBuilder(
            builder: (context, item, playing) => SongRow(
              track: songs[k],
              current: item?.id == songs[k].id,
              playing: playing,
              onTap: () => App.audio.playSongs(songs, start: k, from: title),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
      ]),
    );
  }
}

/// The label paper's color of a slot, for a page's top.
Color paperColor(int slot) => paperFor(slot).$2.isEmpty ? Look.accent : paperFor(slot).$2.first;

// ---------------------------------------------------------------- a mood or a genre

class MoodView extends StatefulWidget {
  const MoodView({super.key, required this.mood});

  final Mood mood;

  @override
  State<MoodView> createState() => _MoodViewState();
}

class _MoodViewState extends State<MoodView> {
  late Future<List<Shelf>> _shelves = Music.mood(widget.mood.params);

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.mood.color | 0xFF000000);
    return Scaffold(
      body: FutureBuilder<List<Shelf>>(
        future: _shelves,
        builder: (context, snap) {
          final shelves = snap.data;
          return CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 150,
              backgroundColor: Color.lerp(Look.bg, color, 0.55),
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(start: 54, bottom: 14),
                title: Text(widget.mood.title, style: Look.ui(22, weight: FontWeight.w900)),
                background: DecoratedBox(decoration: BoxDecoration(gradient: fadeFrom(color))),
              ),
            ),
            if (shelves == null)
              SliverToBoxAdapter(
                child: snap.hasError
                    ? _failed(_offline, () => setState(() => _shelves = Music.mood(widget.mood.params)))
                    : _loading(),
              )
            else
              for (final shelf in shelves) ...[
                SliverToBoxAdapter(child: SectionTitle(shelf.title.isEmpty ? widget.mood.title : shelf.title)),
                SliverToBoxAdapter(child: CardRow(shelf.items)),
              ],
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- search results on a page of their own

class SearchResultsView extends StatelessWidget {
  const SearchResultsView({super.key, required this.query, this.filter = ''});

  final String query;
  final String filter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Look.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('“$query”', style: Look.ui(17, weight: FontWeight.w700)),
      ),
      body: SearchResultsList(query: query, startFilter: filter),
    );
  }
}
