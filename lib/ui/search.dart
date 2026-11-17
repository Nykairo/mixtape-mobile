/// Search: YouTube Music's whole catalog. While typing, its suggestions and the first results; your
/// recent searches before that; the results with YouTube Music's filters (songs, videos, albums, artists,
/// playlists) and the top result first; and, with nothing typed, moods and genres to browse (Spotify's
/// colored tiles).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../importer.dart';
import '../look.dart';
import '../music.dart';
import '../youtube.dart';
import 'add_music.dart';
import 'pages.dart';
import 'shell.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  static final _asked = ValueNotifier<int>(0);

  /// The search field, ready to type in (Ctrl+F on a keyboard).
  static void typeIn() => _asked.value++;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _typing;
  String _query = '';
  List<String> _words = const [];
  List<Item> _quick = const [];
  List<Mood> _moods = const [];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _field.addListener(_typed);
    SearchPage._asked.addListener(_typeIn);
    Music.moods().then((m) {
      if (mounted) setState(() => _moods = m);
    }).catchError((Object _) {});
  }

  void _typeIn() {
    // the tab comes up in this frame: the field takes the keys once it shows
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    SearchPage._asked.removeListener(_typeIn);
    _typing?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed() {
    _typing?.cancel();
    final text = _field.text.trim();
    if (text.isEmpty) {
      setState(() {
        _words = const [];
        _quick = const [];
      });
      return;
    }
    _typing = Timer(const Duration(milliseconds: 220), () async {
      try {
        final (words, items) = await Music.suggest(text);
        if (mounted && _field.text.trim() == text) {
          setState(() {
            _words = words;
            _quick = items.take(4).toList();
          });
        }
      } on Object {
        // offline: Enter still searches
      }
    });
  }

  void _submit(String text) {
    final q = text.trim();
    if (q.isEmpty) return;
    if (Importer.isListLink(q)) {
      // a playlist, an album or a song from Spotify, Deezer or YouTube: read it in, like on the computer
      _focus.unfocus();
      Shell.push(ImportPage(start: q));
      return;
    }
    _field.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    _focus.unfocus();
    App.library.searched(q);
    setState(() => _query = q);
  }

  void _clear() {
    _field.clear();
    setState(() => _query = '');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final typing = _focus.hasFocus;
    final text = _field.text.trim();
    final Widget body;
    if (typing && text.isEmpty) {
      body = _Recent(onPick: _submit);
    } else if (typing) {
      body = ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16), children: [
        if (_words.isEmpty)
          ListTile(
            leading: const Icon(Icons.search_rounded, color: Look.muted),
            title: Text('Search for “$text”', style: Look.ui(15.5)),
            onTap: () => _submit(text),
          ),
        for (final w in _words)
          ListTile(
            leading: const Icon(Icons.search_rounded, color: Look.muted),
            title: Text(w, style: Look.ui(15.5)),
            trailing: IconButton(
              tooltip: 'Fill in',
              icon: const Icon(Icons.north_west_rounded, size: 20, color: Look.faint),
              onPressed: () {
                _field.value = TextEditingValue(text: '$w ', selection: TextSelection.collapsed(offset: w.length + 1));
              },
            ),
            onTap: () => _submit(w),
          ),
        if (_quick.isNotEmpty) const Divider(indent: 16, endIndent: 16),
        for (final it in _quick) ItemRow(it, list: _quick),
      ]);
    } else if (_query.isNotEmpty) {
      body = SearchResultsList(key: ValueKey(_query), query: _query);
    } else {
      body = _Browse(moods: _moods);
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: typing || _query.isNotEmpty
                ? const SizedBox(width: double.infinity, height: 8)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                    child: Row(children: [
                      Text('Search', style: Look.ui(28, weight: FontWeight.w900)),
                    ]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Row(children: [
              if (typing || _query.isNotEmpty)
                IconButton(
                  tooltip: 'Back',
                  onPressed: () {
                    _field.clear();
                    _focus.unfocus();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.arrow_back_rounded, color: Look.cream),
                ),
              Expanded(
                child: TextField(
                  controller: _field,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submit,
                  style: Look.ui(16, weight: FontWeight.w600, color: Look.bg),
                  cursorColor: Look.accent,
                  decoration: InputDecoration(
                    hintText: 'What do you want to hear?',
                    hintStyle: Look.ui(16, weight: FontWeight.w500, color: const Color(0xFF6B5D50)),
                    filled: true,
                    fillColor: Look.cream,
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF3A3029)),
                    suffixIcon: text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: _clear,
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF3A3029)),
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    enabledBorder:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Look.accent, width: 2)),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

/// What was searched for lately.
class _Recent extends StatelessWidget {
  const _Recent({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.library,
      builder: (context, _) {
        final lib = App.library;
        if (lib.searches.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text('Songs, artists, albums, playlists: all of YouTube Music.',
                textAlign: TextAlign.center, style: Look.ui(15, color: Look.muted, height: 1.4)),
          );
        }
        return ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 8, 4),
            child: Row(children: [
              Expanded(child: Text('Recent searches', style: Look.ui(17, weight: FontWeight.w800))),
              TextButton(onPressed: () => lib.forgetSearch(), child: const Text('Clear')),
            ]),
          ),
          for (final q in lib.searches)
            ListTile(
              leading: const Icon(Icons.history_rounded, color: Look.muted),
              title: Text(q, style: Look.ui(15.5)),
              trailing: IconButton(
                tooltip: 'Forget',
                icon: const Icon(Icons.close_rounded, size: 20, color: Look.faint),
                onPressed: () => lib.forgetSearch(q),
              ),
              onTap: () => onPick(q),
            ),
        ]);
      },
    );
  }
}

/// Moods and genres to browse, in their own colors, with a little cassette tilted into each corner.
class _Browse extends StatelessWidget {
  const _Browse({required this.moods});

  final List<Mood> moods;

  @override
  Widget build(BuildContext context) {
    if (moods.isEmpty) {
      return Center(child: Text('Type to search YouTube Music.', style: Look.ui(15, color: Look.muted)));
    }
    final moodsFirst = [...moods.where((m) => !m.genre), ...moods.where((m) => m.genre)];
    return CustomScrollView(slivers: [
      const SliverToBoxAdapter(child: SectionTitle('Browse all', over: 'Moods, moments and genres')),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        sliver: SliverGrid.builder(
          // two side by side on a phone, more on an unfolded foldable or a tablet
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.75,
          ),
          itemCount: moodsFirst.length,
          itemBuilder: (context, k) => _MoodTile(moodsFirst[k], slot: k),
        ),
      ),
      SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
    ]);
  }
}

class _MoodTile extends StatelessWidget {
  const _MoodTile(this.mood, {required this.slot});

  final Mood mood;
  final int slot;

  @override
  Widget build(BuildContext context) {
    final c = Color(mood.color | 0xFF000000);
    final hsv = HSVColor.fromColor(c);
    final bg = hsv.withValue(min(hsv.value, 0.62)).withSaturation(min(1.0, hsv.saturation * 1.1)).toColor();
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Shell.push(MoodView(mood: mood)),
        child: Stack(children: [
          Positioned(
            right: -16,
            bottom: -6,
            width: 84,
            child: Transform.rotate(
              angle: 0.42,
              child: IgnorePointer(child: TapeArtPlain(title: '', slot: slot % 10)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(mood.title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(16.5, weight: FontWeight.w800, height: 1.15)),
          ),
        ]),
      ),
    );
  }
}

/// The results of a search, with YouTube Music's filters over them.
class SearchResultsList extends StatefulWidget {
  const SearchResultsList({super.key, required this.query, this.startFilter = ''});

  final String query;
  final String startFilter;

  @override
  State<SearchResultsList> createState() => _SearchResultsListState();
}

class _SearchResultsListState extends State<SearchResultsList> {
  // Lyrics finds a song from a line of its words: YouTube Music's song search reads the words too
  static const _filters = [
    ('', 'All'),
    ('songs', 'Songs'),
    ('lyrics', 'Lyrics'),
    ('videos', 'Videos'),
    ('albums', 'Albums'),
    ('artists', 'Artists'),
    ('playlists', 'Playlists'),
  ];

  late String _filter = widget.startFilter;
  final _results = <String, SearchResults>{};
  final _busy = <String>{};
  String? _trouble;

  @override
  void initState() {
    super.initState();
    _load(_filter);
  }

  Future<void> _load(String filter, {bool more = false}) async {
    final have = _results[filter];
    if (_busy.contains(filter) || (more && have == null) || (have != null && (!more || have.more.isEmpty))) return;
    _busy.add(filter);
    setState(() => _trouble = null);
    try {
      var got = await Music.search(widget.query, filter: filter == 'lyrics' ? 'songs' : filter, more: more ? have!.more : '');
      // no song knows these words: maybe a lyrics video does
      if (filter == 'lyrics' && !more && got.items.isEmpty) {
        got = await Music.search('${widget.query} lyrics', filter: 'videos');
      }
      if (!mounted) return;
      setState(() {
        _results[filter] = have == null || !more ? got : SearchResults(have.top, [...have.items, ...got.items], got.more);
      });
    } on YouTubeError catch (e) {
      if (mounted) {
        setState(() => _trouble = e.why == 'network'
            ? "Can't reach YouTube Music. Check the internet connection."
            : e.why == 'busy'
                ? 'YouTube asks to slow down for a moment. Try again in a minute.'
                : "YouTube Music didn't answer that search. Try again.");
      }
    } finally {
      _busy.remove(filter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _results[_filter];
    return Column(children: [
      SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
          children: [
            for (final (key, name) in _filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(name),
                  selected: _filter == key,
                  showCheckmark: false,
                  labelStyle: Look.ui(13.5, weight: FontWeight.w600, color: _filter == key ? Look.bg : Look.cream),
                  selectedColor: Look.cream,
                  backgroundColor: Look.raised,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  onSelected: (_) {
                    setState(() => _filter = key);
                    _load(key);
                  },
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: r == null
            ? (_trouble != null
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(_trouble!, textAlign: TextAlign.center, style: Look.ui(15, color: Look.muted)),
                  )
                : const Center(child: CircularProgressIndicator()))
            : NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 500 && r.more.isNotEmpty) _load(_filter, more: true);
                  return false;
                },
                child: r.items.isEmpty && r.top == null
                    ? Center(child: Text('Nothing found. Try other words.', style: Look.ui(15, color: Look.muted)))
                    : ListView.builder(
                        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16),
                        itemCount: r.items.length + (r.top != null ? 1 : 0) + (r.more.isNotEmpty ? 1 : 0) + (_filter == 'lyrics' ? 1 : 0),
                        itemBuilder: (context, k) {
                          if (_filter == 'lyrics') {
                            if (k == 0) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                child: Text('Songs with “${widget.query}” in their words',
                                    style: Look.ui(13.5, color: Look.muted)),
                              );
                            }
                            k--;
                          }
                          if (r.top != null) {
                            if (k == 0) return _Top(r.top!, related: r.items);
                            k--;
                          }
                          if (k >= r.items.length) {
                            return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                          }
                          return ItemRow(r.items[k], list: r.items);
                        },
                      ),
              ),
      ),
    ]);
  }
}

/// The top result, big, the way YouTube Music shows it, with a button to play it right away.
class _Top extends StatelessWidget {
  const _Top(this.item, {required this.related});

  final Item item;
  final List<Item> related;

  Future<void> _play(BuildContext context) async {
    if (item.playable) {
      await App.audio.playSongs([item.track], from: '${item.title} radio');
    } else if (item.kind == Kind.artist) {
      try {
        final a = await Music.artist(item.id);
        await App.audio.playSongs(a.songs, from: a.name);
      } on Object {
        if (context.mounted) say(context, "Couldn't reach YouTube Music");
      }
    } else {
      try {
        final l = await Music.list(item.id);
        await App.audio.playSongs(l.songs, from: l.title);
      } on Object {
        if (context.mounted) say(context, "Couldn't reach YouTube Music");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final round = item.kind == Kind.artist;
    final kind = switch (item.kind) {
      Kind.artist => 'Artist',
      Kind.album => 'Album',
      Kind.playlist => 'Playlist',
      Kind.video => 'Video',
      _ => 'Song',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Material(
        color: Look.raised,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openItem(context, item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Pic(item.art, size: 84, radius: 8, round: round, icon: round ? Icons.person_rounded : null),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(19, weight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text([kind, if (item.subtitle.isNotEmpty) item.subtitle].join('  ·  '),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              Material(
                color: Look.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _play(context),
                  child: const SizedBox.square(dimension: 46, child: Icon(Icons.play_arrow_rounded, color: Look.bg, size: 28)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
