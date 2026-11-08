/// YouTube Music for the pages: what a search, an artist, an album, a playlist, the home page, the moods
/// and a song's radio hold, read out of InnerTube's answers (innertube.dart asks, this reads).
library;

import 'dart:async';

import 'innertube.dart';
import 'jsonwalk.dart';
import 'model.dart';
import 'youtube.dart';

enum Kind { song, video, album, artist, playlist, other }

/// One thing YouTube Music shows: a song or a video (to play), an album, an artist or a playlist (to open).
class Item {
  const Item({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.art = '',
    this.artist = '',
    this.artistId = '',
    this.album = '',
    this.albumId = '',
    this.dur = 0,
    this.views = 0,
    this.official = false,
  });

  final Kind kind;

  /// The video id of a song or a video, the browse id of the rest (UC..., MPREb..., VL...).
  final String id;
  final String title;

  /// The line under it, as YouTube words it ("Album • 2013", "Daft Punk • 12M views").
  final String subtitle;
  final String art;
  final String artist;
  final String artistId;
  final String album;
  final String albumId;
  final int dur;

  /// Views or plays, when it says.
  final double views;

  /// An official music video (from the artist's own channel).
  final bool official;

  bool get playable => kind == Kind.song || kind == Kind.video;

  Track get track => Track(src: 'yt', ref: id, title: title, artist: artist, art: art, dur: dur, extra: {
        if (album.isNotEmpty) 'album': album,
        if (albumId.isNotEmpty) 'album_id': albumId,
        if (artistId.isNotEmpty) 'artist_id': artistId,
      });
}

/// A row of things with a heading ("Albums", "Fans might also like", "Throwbacks").
class Shelf {
  const Shelf(this.title, this.items, {this.subtitle = '', this.more = ''});

  final String title;
  final String subtitle;
  final List<Item> items;

  /// The page with all of them, when there is one.
  final String more;
}

class SearchResults {
  const SearchResults(this.top, this.items, this.more);

  final Item? top;
  final List<Item> items;

  /// Where the results go on ('' at the end).
  final String more;
}

class ArtistPage {
  const ArtistPage({
    required this.id,
    required this.name,
    this.art = '',
    this.audience = '',
    this.about = '',
    this.songs = const [],
    this.allSongs = '',
    this.shelves = const [],
    this.radio = '',
    this.radioSeed = '',
  });

  final String id;
  final String name;
  final String art;
  final String audience;
  final String about;
  final List<Track> songs;

  /// The playlist with all the artist's songs.
  final String allSongs;
  final List<Shelf> shelves;

  /// The artist's mix (a radio playlist) and the song it starts from.
  final String radio;
  final String radioSeed;
}

/// An album or a playlist.
class ListPage {
  const ListPage({
    required this.id,
    required this.title,
    this.kind = Kind.album,
    this.subtitle = '',
    this.second = '',
    this.art = '',
    this.artist = '',
    this.artistId = '',
    this.about = '',
    this.songs = const [],
    this.more = '',
  });

  final String id;
  final String title;
  final Kind kind;
  final String subtitle;
  final String second;
  final String art;
  final String artist;
  final String artistId;
  final String about;
  final List<Track> songs;
  final String more;

  ListPage withMore(List<Track> extra, String next) => ListPage(
      id: id,
      title: title,
      kind: kind,
      subtitle: subtitle,
      second: second,
      art: art,
      artist: artist,
      artistId: artistId,
      about: about,
      songs: [...songs, ...extra],
      more: next);
}

/// A mood or a genre from YouTube Music's Explore page.
class Mood {
  const Mood(this.title, this.color, this.params, {this.genre = false});

  final String title;
  final int color;
  final String params;
  final bool genre;
}

class HomeFeed {
  const HomeFeed(this.chips, this.shelves);

  /// (name, params): Relax, Energize, Workout...
  final List<(String, String)> chips;
  final List<Shelf> shelves;
}

/// What plays after a song (its radio), and its lyrics and related pages.
class WatchNext {
  const WatchNext(this.songs, {this.lyrics = '', this.related = ''});

  final List<Track> songs;
  final String lyrics;
  final String related;
}

// ---------------------------------------------------------------- asking, with a short memory

class Music {
  static InnerTube get _yt => YouTube.inner;
  static final _cache = <String, (DateTime, Object)>{};

  static Future<T> _kept<T extends Object>(String key, Duration life, Future<T> Function() ask) async {
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < life && hit.$2 is T) return hit.$2 as T;
    final value = await _guard(ask);
    _cache[key] = (DateTime.now(), value);
    while (_cache.length > 60) {
      _cache.remove(_cache.keys.first);
    }
    return value;
  }

  static Future<T> _guard<T>(Future<T> Function() ask) async {
    try {
      return await ask();
    } on InnerTubeError catch (e) {
      throw YouTubeError(e.why, e.detail);
    }
  }

  static Future<SearchResults> search(String query, {String filter = '', String more = ''}) =>
      _kept('s:$filter:$query:$more', const Duration(minutes: 20),
          () async => parseSearch(await _yt.searchRaw(query, filter: filter, more: more)));

  /// What to offer under the search box while typing: words to search for, and a few results already.
  static Future<(List<String>, List<Item>)> suggest(String input) => _kept('q:$input', const Duration(minutes: 30),
      () async => parseSuggestions(await _yt.suggestRaw(input)));

  static Future<ArtistPage> artist(String id) =>
      _kept('a:$id', const Duration(minutes: 30), () async => parseArtist(await _yt.browseRaw(id), id));

  /// An album (MPREb...) or a playlist (VL..., or a bare PL..., OLAK..., RD...).
  static Future<ListPage> list(String id) {
    final browse = id.startsWith('MPRE') || id.startsWith('VL') || id.startsWith('FE') ? id : 'VL$id';
    return _kept('l:$browse', const Duration(minutes: 30), () async => parseList(await _yt.browseRaw(browse), browse));
  }

  /// The rest of a long playlist.
  static Future<ListPage> more(ListPage page) async {
    if (page.more.isEmpty) return page;
    final data = await _guard(() => _yt.browseRaw('', more: page.more));
    final (songs, next) = parseListMore(data, page);
    return page.withMore(songs, next);
  }

  static Future<HomeFeed> home({String params = ''}) =>
      _kept('h:$params', const Duration(minutes: 30), () async => parseHome(await _yt.browseRaw('FEmusic_home', params: params)));

  static Future<List<Mood>> moods() => _kept(
      'moods', const Duration(hours: 12), () async => parseMoods(await _yt.browseRaw('FEmusic_moods_and_genres')));

  static Future<List<Shelf>> mood(String params) => _kept('m:$params', const Duration(hours: 2),
      () async => parseShelves(await _yt.browseRaw('FEmusic_moods_and_genres_category', params: params)));

  static Future<WatchNext> next(String videoId, {String playlist = '', String params = ''}) =>
      _kept('n:$videoId:$playlist', const Duration(minutes: 20),
          () async => parseNext(await _yt.nextRaw(videoId, playlist: playlist, params: params), videoId));

  static Future<List<Shelf>> related(String relatedId) =>
      _kept('r:$relatedId', const Duration(hours: 1), () async => parseShelves(await _yt.browseRaw(relatedId)));
}

// ---------------------------------------------------------------- reading the answers

const _typeWords = {
  'Song': Kind.song,
  'Video': Kind.video,
  'Album': Kind.album,
  'Single': Kind.album,
  'EP': Kind.album,
  'Artist': Kind.artist,
  'Playlist': Kind.playlist,
  'Episode': Kind.other,
  'Podcast': Kind.other,
  'Profile': Kind.other,
  'Station': Kind.other,
};

Kind _pageKind(String pageType) => switch (pageType) {
      'MUSIC_PAGE_TYPE_ALBUM' || 'MUSIC_PAGE_TYPE_AUDIOBOOK' => Kind.album,
      'MUSIC_PAGE_TYPE_ARTIST' || 'MUSIC_PAGE_TYPE_LIBRARY_ARTIST' => Kind.artist,
      'MUSIC_PAGE_TYPE_PLAYLIST' => Kind.playlist,
      _ => Kind.other,
    };

/// A run of text with where it links to: (text, browse id, page type).
typedef _Run = (String, String, String);

List<_Run> _linked(Object? text) => [
      for (final r in asList(asMap(text)['runs']))
        if (r is Map) _run(Map<String, Object?>.from(r)),
    ];

_Run _run(Map<String, Object?> r) {
  final browse = asMap(asMap(r['navigationEndpoint'])['browseEndpoint']);
  final type = '${asMap(asMap(browse['browseEndpointContextSupportedConfigs'])['browseEndpointContextMusicConfig'])['pageType'] ?? ''}';
  return ('${r['text'] ?? ''}', '${browse['browseId'] ?? ''}', type);
}

double _count(String text) {
  final m = RegExp(r'([\d.,]+)\s*([KMB]?)', caseSensitive: false).firstMatch(text);
  if (m == null) return 0;
  final n = double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
  return n * (const {'': 1, 'K': 1e3, 'M': 1e6, 'B': 1e9}[m.group(2)!.toUpperCase()] ?? 1);
}

String _videoType(Object? node) => '${findOne(node, 'watchEndpointMusicConfig')['musicVideoType'] ?? ''}';

/// What the parts of a subtitle say: the artists (linked or the first plain part), the album, a year,
/// a length and a view count.
class _Parts {
  _Parts(List<_Run> runs, {bool firstIsArtist = true}) {
    final words = runs.map((r) => r.$1).join().split(' • ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (words.isNotEmpty && _typeWords.containsKey(words.first)) type = _typeWords[words.first];
    for (final r in runs) {
      if (r.$3 == 'MUSIC_PAGE_TYPE_ARTIST' || r.$3 == 'MUSIC_PAGE_TYPE_USER_CHANNEL') {
        if (artist.isEmpty) artistId = r.$2;
        artists.add(r.$1);
      } else if (r.$3 == 'MUSIC_PAGE_TYPE_ALBUM' && album.isEmpty) {
        album = r.$1;
        albumId = r.$2;
      }
    }
    for (final w in words) {
      if (isClock(w)) {
        dur = clockSeconds(w);
      } else if (RegExp(r'^\d{4}$').hasMatch(w)) {
        year = w;
      } else if (RegExp(r'\b(views|plays|listeners|monthly audience)$').hasMatch(w)) {
        views = _count(w);
      }
    }
    if (artists.isEmpty && firstIsArtist) {
      final plain = words.where((w) => !_typeWords.containsKey(w) && !isClock(w) && !RegExp(r'^\d{4}$').hasMatch(w));
      if (plain.isNotEmpty && !RegExp(r'\b(views|plays)$').hasMatch(plain.first)) artists.add(plain.first);
    }
    shown = words.where((w) => !_typeWords.containsKey(w) || words.length == 1).join(' • ');
  }

  Kind? type;
  final List<String> artists = [];
  String artistId = '';
  String album = '';
  String albumId = '';
  String year = '';
  int dur = 0;
  double views = 0;
  String shown = '';

  String get artist => artists.join(', ');
}

/// A list row (musicResponsiveListItemRenderer): a song or video to play, or a thing to open.
Item? rowItem(Map<String, Object?> r, {String art = '', String artist = '', String album = '', String albumId = ''}) {
  final cols = [
    for (final c in asList(r['flexColumns'])) asMap(asMap(c)['musicResponsiveListItemFlexColumnRenderer'])['text'],
  ];
  if (cols.isEmpty) return null;
  final title = textOf(cols.first);
  if (title.isEmpty) return null;
  final runs = <_Run>[];
  for (var k = 1; k < cols.length; k++) {
    final more = _linked(cols[k]);
    if (more.isEmpty) continue;
    if (runs.isNotEmpty) runs.add((' • ', '', ''));
    runs.addAll(more);
  }
  final parts = _Parts(runs);
  for (final c in asList(r['fixedColumns'])) {
    final t = textOf(asMap(asMap(c)['musicResponsiveListItemFixedColumnRenderer'])['text']);
    if (isClock(t)) parts.dur = clockSeconds(t);
  }
  final picture = thumbOf(r['thumbnail']);
  var vid = '${asMap(r['playlistItemData'])['videoId'] ?? ''}';
  if (vid.isEmpty) vid = '${findOne(r['overlay'], 'watchEndpoint')['videoId'] ?? ''}';
  if (vid.isEmpty) vid = '${findOne(cols.first, 'watchEndpoint')['videoId'] ?? ''}';
  if (vid.isNotEmpty) {
    final vt = _videoType(r);
    final kind = vt == 'MUSIC_VIDEO_TYPE_ATV'
        ? Kind.song
        : vt == 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE'
            ? Kind.other
            : vt.isNotEmpty
                ? Kind.video
                : (parts.type ?? Kind.song);
    return Item(
      kind: kind,
      id: vid,
      title: title,
      subtitle: parts.shown,
      art: picture.isEmpty ? art : picture,
      artist: parts.artist.isEmpty ? artist : parts.artist,
      artistId: parts.artistId,
      album: parts.album.isEmpty ? album : parts.album,
      albumId: parts.albumId.isEmpty ? albumId : parts.albumId,
      dur: parts.dur,
      views: parts.views,
      official: vt == 'MUSIC_VIDEO_TYPE_OMV',
    );
  }
  final (id, type) = _browseTarget(r['navigationEndpoint']);
  if (id.isEmpty) return null;
  final kind = _pageKind(type) != Kind.other ? _pageKind(type) : (parts.type ?? Kind.other);
  return Item(
      kind: kind,
      id: id,
      title: title,
      subtitle: parts.shown,
      art: picture,
      artist: kind == Kind.artist ? title : parts.artist,
      artistId: kind == Kind.artist ? id : parts.artistId,
      views: parts.views);
}

(String, String) _browseTarget(Object? endpoint) {
  final b = asMap(asMap(endpoint)['browseEndpoint']);
  final type = '${asMap(asMap(b['browseEndpointContextSupportedConfigs'])['browseEndpointContextMusicConfig'])['pageType'] ?? ''}';
  return ('${b['browseId'] ?? ''}', type);
}

/// A card in a row (musicTwoRowItemRenderer): an album, a playlist, an artist, or a video to play.
Item? cardItem(Map<String, Object?> c, {String artist = '', String artistId = ''}) {
  final title = textOf(c['title']);
  if (title.isEmpty) return null;
  final runs = _linked(c['subtitle']);
  final parts = _Parts(runs, firstIsArtist: false);
  final art = thumbOf(c['thumbnailRenderer']);
  final nav = asMap(c['navigationEndpoint']);
  final watch = asMap(nav['watchEndpoint']);
  if (watch['videoId'] is String) {
    final vt = _videoType(nav);
    final p = _Parts(runs);
    return Item(
      kind: vt == 'MUSIC_VIDEO_TYPE_ATV' ? Kind.song : Kind.video,
      id: '${watch['videoId']}',
      title: title,
      subtitle: p.shown,
      art: art,
      artist: p.artist.isEmpty ? artist : p.artist,
      artistId: p.artistId.isEmpty ? artistId : p.artistId,
      views: p.views,
      official: vt == 'MUSIC_VIDEO_TYPE_OMV',
    );
  }
  final (id, type) = _browseTarget(nav);
  if (id.isEmpty) return null;
  final kind = _pageKind(type);
  if (kind == Kind.other) return null;
  return Item(
    kind: kind,
    id: id,
    title: title,
    subtitle: parts.shown,
    art: art,
    artist: kind == Kind.artist ? title : (parts.artist.isEmpty ? artist : parts.artist),
    artistId: kind == Kind.artist ? id : (parts.artistId.isEmpty ? artistId : parts.artistId),
    views: parts.views,
  );
}

/// The big card over the search results (musicCardShelfRenderer).
Item? topItem(Map<String, Object?> card) {
  final title = textOf(card['title']);
  if (title.isEmpty) return null;
  final runs = _linked(card['subtitle']);
  final parts = _Parts(runs);
  final art = thumbOf(card['thumbnail']);
  final titleRun = _linked(card['title']);
  final (id, type) = titleRun.isNotEmpty && titleRun.first.$2.isNotEmpty
      ? (titleRun.first.$2, titleRun.first.$3)
      : _browseTarget(card['onTap'] ?? card['navigationEndpoint']);
  var watch = findOne(card['title'], 'watchEndpoint');
  if (watch.isEmpty) watch = findOne(card['onTap'], 'watchEndpoint');
  if (watch['videoId'] is String) {
    var vt = _videoType(card['title']);
    if (vt.isEmpty) vt = _videoType(card['onTap']);
    return Item(
      kind: vt == 'MUSIC_VIDEO_TYPE_ATV' || parts.type == Kind.song ? Kind.song : Kind.video,
      id: '${watch['videoId']}',
      title: title,
      subtitle: parts.shown,
      art: art,
      artist: parts.artist,
      artistId: parts.artistId,
      album: parts.album,
      albumId: parts.albumId,
      dur: parts.dur,
      views: parts.views,
      official: vt == 'MUSIC_VIDEO_TYPE_OMV',
    );
  }
  if (id.isEmpty) return null;
  final kind = _pageKind(type) != Kind.other ? _pageKind(type) : (parts.type ?? Kind.other);
  return Item(
    kind: kind,
    id: id,
    title: title,
    subtitle: parts.shown,
    art: art,
    artist: kind == Kind.artist ? title : parts.artist,
    artistId: kind == Kind.artist ? id : parts.artistId,
    views: parts.views,
  );
}

SearchResults parseSearch(Map<String, Object?> data) {
  Item? top;
  final items = <Item>[];
  final seen = <String>{};
  for (final card in findAll(data, 'musicCardShelfRenderer')) {
    top ??= topItem(card);
    for (final r in findAll(card['contents'], 'musicResponsiveListItemRenderer')) {
      final it = rowItem(r);
      if (it != null && it.kind != Kind.other && seen.add(it.id)) items.add(it);
    }
  }
  if (top != null) seen.add(top.id);
  for (final r in findAll(data, 'musicResponsiveListItemRenderer')) {
    final it = rowItem(r);
    if (it != null && it.kind != Kind.other && seen.add(it.id)) items.add(it);
  }
  var more = '';
  for (final c in findAll(data, 'nextContinuationData')) {
    more = '${c['continuation'] ?? ''}';
    break;
  }
  return SearchResults(top, items, more);
}

(List<String>, List<Item>) parseSuggestions(Map<String, Object?> data) {
  final words = [
    for (final s in findAll(data, 'searchSuggestionRenderer')) textOf(s['suggestion']),
  ].where((w) => w.isNotEmpty).toList();
  final items = [
    for (final r in findAll(data, 'musicResponsiveListItemRenderer'))
      if (rowItem(r) case final Item it)
        if (it.kind != Kind.other) it,
  ];
  return (words, items);
}

/// Whatever kind of item a shelf holds.
Item? _anyItem(Object? x, {String artist = '', String artistId = ''}) {
  final m = asMap(x);
  final card = m['musicTwoRowItemRenderer'];
  if (card is Map) return cardItem(Map<String, Object?>.from(card), artist: artist, artistId: artistId);
  final row = m['musicResponsiveListItemRenderer'];
  if (row is Map) return rowItem(Map<String, Object?>.from(row), artist: artist);
  return null;
}

List<Shelf> _shelvesIn(Object? data, {String artist = '', String artistId = ''}) {
  final out = <Shelf>[];
  for (final c in findAll(data, 'musicCarouselShelfRenderer')) {
    final header = findOne(c['header'], 'musicCarouselShelfBasicHeaderRenderer');
    final items = <Item>[
      for (final x in asList(c['contents']))
        if (_anyItem(x, artist: artist, artistId: artistId) case final Item it)
          if (it.kind != Kind.other) it,
    ];
    final (more, _) = _browseTarget(findOne(header['moreContentButton'], 'buttonRenderer')['navigationEndpoint']);
    if (items.isNotEmpty) {
      out.add(Shelf(textOf(header['title']), items, subtitle: textOf(header['strapline']), more: more));
    }
  }
  for (final g in findAll(data, 'gridRenderer')) {
    final items = <Item>[
      for (final x in asList(g['items']))
        if (_anyItem(x) case final Item it)
          if (it.kind != Kind.other) it,
    ];
    if (items.isNotEmpty) out.add(Shelf(textOf(findOne(g['header'], 'gridHeaderRenderer')['title']), items));
  }
  return out;
}

ArtistPage parseArtist(Map<String, Object?> data, String id) {
  var header = findOne(data['header'], 'musicImmersiveHeaderRenderer');
  if (header.isEmpty) header = findOne(data['header'], 'musicVisualHeaderRenderer');
  final name = textOf(header['title']);
  final radio = findOne(header['startRadioButton'], 'watchEndpoint');
  final songs = <Track>[];
  var allSongs = '';
  for (final shelf in findAll(data, 'musicShelfRenderer')) {
    for (final r in findAll(shelf['contents'], 'musicResponsiveListItemRenderer')) {
      final it = rowItem(r, artist: name);
      if (it != null && it.playable) songs.add(it.track);
    }
    var (more, _) = _browseTarget(shelf['bottomEndpoint']);
    if (more.isEmpty) more = '${findOne(shelf['title'], 'browseEndpoint')['browseId'] ?? ''}';
    allSongs = more;
    break; // the first list is the top songs
  }
  var about = textOf(header['description']);
  for (final d in findAll(data, 'musicDescriptionShelfRenderer')) {
    about = textOf(d['description']);
  }
  return ArtistPage(
    id: id,
    name: name,
    art: thumbOf(header['thumbnail']),
    audience: textOf(header['monthlyListenerCount']),
    about: about,
    songs: songs,
    allSongs: allSongs,
    shelves: _shelvesIn(data['contents'], artist: name, artistId: id),
    radio: '${radio['playlistId'] ?? ''}',
    radioSeed: '${radio['videoId'] ?? ''}',
  );
}

ListPage parseList(Map<String, Object?> data, String id) {
  var header = findOne(data, 'musicResponsiveHeaderRenderer');
  if (header.isEmpty) header = findOne(data, 'musicDetailHeaderRenderer');
  final title = textOf(header['title']);
  final subtitle = textOf(header['subtitle']);
  final by = _linked(header['straplineTextOne']);
  final subRuns = _linked(header['subtitle']);
  final artistRun = [...by, ...subRuns].where((r) => r.$3 == 'MUSIC_PAGE_TYPE_ARTIST' || r.$3 == 'MUSIC_PAGE_TYPE_USER_CHANNEL');
  final artist = by.isNotEmpty ? by.map((r) => r.$1).join() : (artistRun.isEmpty ? '' : artistRun.first.$1);
  final art = thumbOf(header['thumbnail']);
  final shelf = findOne(header['description'], 'musicDescriptionShelfRenderer');
  final about = textOf(shelf.isEmpty ? header['description'] : shelf['description']);
  final album = id.startsWith('MPRE');
  final songs = <Track>[];
  var more = '';
  final shelves = [...findAll(data, 'musicShelfRenderer'), ...findAll(data, 'musicPlaylistShelfRenderer')];
  if (shelves.isNotEmpty) {
    final shelf = shelves.first;
    for (final r in findAll(shelf['contents'], 'musicResponsiveListItemRenderer')) {
      final it = rowItem(r, art: album ? art : '', artist: artist, album: album ? title : '', albumId: album ? id : '');
      if (it != null && it.playable) songs.add(it.track);
    }
    more = _continuation(shelf);
  }
  return ListPage(
    id: id,
    title: title,
    kind: album ? Kind.album : Kind.playlist,
    subtitle: subtitle,
    second: textOf(header['secondSubtitle']),
    art: art,
    artist: artist,
    artistId: artistRun.isEmpty ? '' : artistRun.first.$2,
    about: about,
    songs: songs,
    more: more,
  );
}

String _continuation(Object? node) {
  for (final c in findAll(node, 'continuationCommand')) {
    final t = c['token'];
    if (t is String && t.isNotEmpty) return t;
  }
  for (final c in findAll(node, 'nextContinuationData')) {
    final t = c['continuation'];
    if (t is String && t.isNotEmpty) return t;
  }
  return '';
}

(List<Track>, String) parseListMore(Map<String, Object?> data, ListPage page) {
  final album = page.kind == Kind.album;
  final songs = [
    for (final r in findAll(data, 'musicResponsiveListItemRenderer'))
      if (rowItem(r, art: album ? page.art : '', artist: page.artist) case final Item it)
        if (it.playable) it.track,
  ];
  return (songs, songs.isEmpty ? '' : _continuation(data));
}

HomeFeed parseHome(Map<String, Object?> data) {
  final chips = <(String, String)>[];
  for (final c in findAll(data, 'chipCloudChipRenderer')) {
    final name = textOf(c['text']);
    final params = '${findOne(c['navigationEndpoint'], 'browseEndpoint')['params'] ?? ''}';
    if (name.isNotEmpty && params.isNotEmpty) chips.add((name, params));
  }
  return HomeFeed(chips, _shelvesIn(data['contents']));
}

List<Mood> parseMoods(Map<String, Object?> data) {
  final out = <Mood>[];
  for (final g in findAll(data, 'gridRenderer')) {
    final heading = textOf(findOne(g['header'], 'gridHeaderRenderer')['title']).toLowerCase();
    for (final x in asList(g['items'])) {
      final b = asMap(asMap(x)['musicNavigationButtonRenderer']);
      final params = '${findOne(b['clickCommand'], 'browseEndpoint')['params'] ?? ''}';
      final title = textOf(b['buttonText']);
      if (title.isEmpty || params.isEmpty) continue;
      out.add(Mood(title, toInt(asMap(b['solid'])['leftStripeColor'], or: 0xFF888888), params,
          genre: heading.contains('genre')));
    }
  }
  return out;
}

List<Shelf> parseShelves(Map<String, Object?> data) => _shelvesIn(data['contents'] ?? data);

WatchNext parseNext(Map<String, Object?> data, String videoId) {
  final songs = <Track>[];
  final seen = <String>{};
  for (final item in findAll(data, 'playlistPanelVideoRenderer')) {
    final m = InnerTube.panelItem(item);
    if (m == null || !seen.add('${m['id']}')) continue;
    final runs = _linked(item['longBylineText']);
    final parts = _Parts(runs);
    songs.add(Track(
      src: 'yt',
      ref: '${m['id']}',
      title: '${m['title']}',
      artist: parts.artist.isEmpty ? '${m['artist']}' : parts.artist,
      art: '${m['art']}',
      dur: m['dur'] is int ? m['dur'] as int : 0,
      extra: {
        if (parts.album.isNotEmpty) 'album': parts.album,
        if (parts.albumId.isNotEmpty) 'album_id': parts.albumId,
        if (parts.artistId.isNotEmpty) 'artist_id': parts.artistId,
      },
    ));
  }
  var lyrics = '', related = '';
  for (final tab in findAll(data, 'tabRenderer')) {
    final id = '${findOne(tab['endpoint'], 'browseEndpoint')['browseId'] ?? ''}';
    if (id.startsWith('MPLY')) lyrics = id;
    if (id.startsWith('MPTR')) related = id;
  }
  return WatchNext(songs, lyrics: lyrics, related: related);
}
