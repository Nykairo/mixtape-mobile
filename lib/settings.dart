/// What can be set on the phone: the tape stock (the color of what plays), whether the music goes on
/// with songs like the last one when a list runs out (the radio), the crossfade between songs, the
/// lyrics' countdown, whether friends can listen along, what the big player shows (cover, tape or the
/// music video), how the library shows, and whether the word about the phone's battery manager was
/// answered.
library;

import 'package:flutter/foundation.dart';

import 'blend.dart';
import 'look.dart';
import 'store.dart';

const _file = 'settings.json';
const _views = {'cover', 'tape', 'video'};

class Settings extends ChangeNotifier {
  String get stock => Look.stock;
  bool autoplay = true;

  /// Friends with a Mixtape Account can listen along with what plays here.
  bool shareListening = true;

  /// ListenBrainz: the token that sends what you listen to (scrobbling) and the name it belongs to;
  /// and a Last.fm API key, for listening along with people on Last.fm.
  String listenBrainzToken = '';
  String listenBrainzUser = '';
  String lastFmKey = '';

  /// Seconds two songs overlap (0: off), the last length that was on (what switching it on brings
  /// back), the shape of the blend, and whether songs of one album run into each other as made.
  double crossfade = 0;
  double crossfadeWas = 6;
  String fadeShape = 'smooth';
  bool albumsWhole = true;

  /// The little clock next to the lyrics that counts down to the next line.
  bool lyricsCountdown = true;

  /// A word on Home early in the month when last month's Rewind is ready, and the month ('2026-10')
  /// whose word was answered already.
  bool rewindNote = true;
  String rewindSeen = '';

  /// What the big player shows at the top: the song's 'cover', its 'tape', or its music 'video'. Video
  /// mode stays on from one song (and one start of the app) to the next.
  String playerView = 'cover';

  /// The library as a grid of cassettes (or a list), and how it's sorted: 'recent', 'name' or 'songs'.
  bool grid = false;
  String sort = 'recent';

  /// The word on Home about phones whose battery manager stops music was answered (or waved off).
  bool backgroundTipDone = false;

  late final _save = LaterSave(_file, () => {
        'stock': Look.stock,
        'autoplay': autoplay,
        'share_listening': shareListening,
        'crossfade': crossfade,
        'crossfade_was': crossfadeWas,
        'fade_shape': fadeShape,
        'albums_whole': albumsWhole,
        'lyrics_countdown': lyricsCountdown,
        'rewind_note': rewindNote,
        'listenbrainz_token': listenBrainzToken,
        'listenbrainz_user': listenBrainzUser,
        'lastfm_key': lastFmKey,
        'rewind_seen': rewindSeen,
        'player_view': playerView,
        'grid': grid,
        'sort': sort,
        'background_tip_done': backgroundTipDone,
      }, delay: const Duration(milliseconds: 400));

  Future<void> load() async {
    final j = await Store.the.read(_file);
    if (j is Map) {
      final s = j['stock'];
      if (s is String && Look.stocks.containsKey(s)) Look.stock = s;
      autoplay = j['autoplay'] != false;
      shareListening = j['share_listening'] != false;
      crossfade = fadeSecondsOf(j['crossfade']);
      final was = fadeSecondsOf(j['crossfade_was']);
      if (was > 0) crossfadeWas = was;
      fadeShape = fadeShapeOf(j['fade_shape']);
      albumsWhole = j['albums_whole'] != false;
      lyricsCountdown = j['lyrics_countdown'] != false;
      rewindNote = j['rewind_note'] != false;
      listenBrainzToken = '${j['listenbrainz_token'] ?? ''}';
      listenBrainzUser = '${j['listenbrainz_user'] ?? ''}';
      lastFmKey = '${j['lastfm_key'] ?? ''}';
      rewindSeen = '${j['rewind_seen'] ?? ''}';
      final view = j['player_view'];
      if (view is String && _views.contains(view)) playerView = view;
      grid = j['grid'] == true;
      final order = j['sort'];
      if (order is String && const {'recent', 'name', 'songs'}.contains(order)) sort = order;
      backgroundTipDone = j['background_tip_done'] == true;
    }
  }

  void setStock(String name) {
    if (!Look.stocks.containsKey(name) || name == Look.stock) return;
    Look.stock = name;
    _save.soon();
    notifyListeners();
  }

  void setAutoplay(bool on) {
    if (on == autoplay) return;
    autoplay = on;
    _save.soon();
    notifyListeners();
  }

  /// Crossfade: [seconds] 0 switches it off, anything else on at that length (1 to 12, in halves).
  void setCrossfade({double? seconds, String? shape, bool? albums}) {
    if (seconds != null) {
      crossfade = fadeSecondsOf(seconds);
      if (crossfade > 0) crossfadeWas = crossfade;
    }
    if (shape != null) fadeShape = fadeShapeOf(shape);
    if (albums != null) albumsWhole = albums;
    _save.soon();
    notifyListeners();
  }

  void setPlayerView(String view) {
    if (view == playerView || !_views.contains(view)) return;
    playerView = view;
    _save.soon();
    notifyListeners();
  }

  void setLyricsCountdown(bool on) {
    if (on == lyricsCountdown) return;
    lyricsCountdown = on;
    _save.soon();
    notifyListeners();
  }

  void setRewindNote(bool on) {
    if (on == rewindNote) return;
    rewindNote = on;
    _save.soon();
    notifyListeners();
  }

  /// ListenBrainz on (a checked token and its name) or off (both empty).
  void setListenBrainz(String token, String user) {
    listenBrainzToken = token.trim();
    listenBrainzUser = user;
    _save.soon();
    notifyListeners();
  }

  void setLastFmKey(String key) {
    lastFmKey = key.trim();
    _save.soon();
    notifyListeners();
  }

  void setRewindSeen(String month) {
    if (month == rewindSeen) return;
    rewindSeen = month;
    _save.soon();
    notifyListeners();
  }

  void setShareListening(bool on) {
    if (on == shareListening) return;
    shareListening = on;
    _save.soon();
    notifyListeners();
  }

  void setLibraryView({bool? grid, String? sort}) {
    if (grid != null) this.grid = grid;
    if (sort != null) this.sort = sort;
    _save.soon();
    notifyListeners();
  }

  void setBackgroundTipDone() {
    if (backgroundTipDone) return;
    backgroundTipDone = true;
    _save.soon();
    notifyListeners();
  }

  Future<void> flush() => _save.now();
}
