/// The words YouTube Music writes around names, in the languages it answers the phone in: what kind of
/// thing a row is ("Song", "Titel", "Canción", "曲") and how often it was played or watched ("1.2M views",
/// "1,2 Mio. Aufrufe", "12 mil reproducciones", "4,5万回視聴", "조회수 120만회"). Both stand in the same
/// line as the artist, and neither may ever pass for one. The desktop keeps the same lists (ytwords.py).
library;

/// The word in front of a row, and what it says the row is: 'song', 'video', 'album', 'artist',
/// 'playlist' or 'other' (episodes, podcasts, profiles, stations).
const kindWords = {
  // English
  'Song': 'song', 'Video': 'video', 'Album': 'album', 'Single': 'album', 'EP': 'album', 'Artist': 'artist',
  'Playlist': 'playlist', 'Episode': 'other', 'Podcast': 'other', 'Profile': 'other', 'Station': 'other',
  // German
  'Titel': 'song', 'Künstler': 'artist', 'Folge': 'other', 'Profil': 'other', 'Sender': 'other',
  // Spanish
  'Canción': 'song', 'Vídeo': 'video', 'Álbum': 'album', 'Sencillo': 'album', 'Artista': 'artist',
  'Lista de reproducción': 'playlist', 'Episodio': 'other', 'Pódcast': 'other', 'Perfil': 'other', 'Emisora': 'other',
  // French
  'Titre': 'song', 'Morceau': 'song', 'Vidéo': 'video', 'Artiste': 'artist', 'Épisode': 'other',
  // Italian
  'Brano': 'song', 'Singolo': 'album', 'Puntata': 'other', 'Profilo': 'other', 'Stazione': 'other',
  // Portuguese
  'Música': 'song', 'Episódio': 'other', 'Estação': 'other',
  // Polish
  'Utwór': 'song', 'Film': 'video', 'Wideo': 'video', 'Singiel': 'album', 'Wykonawca': 'artist', 'Artysta': 'artist',
  'Playlista': 'playlist', 'Odcinek': 'other', 'Stacja': 'other',
  // Turkish
  'Şarkı': 'song', 'Albüm': 'album', 'Tekli': 'album', 'Sanatçı': 'artist', 'Oynatma listesi': 'playlist',
  'Çalma listesi': 'playlist', 'Bölüm': 'other', 'İstasyon': 'other',
  // Dutch
  'Nummer': 'song', 'Artiest': 'artist', 'Aflevering': 'other', 'Profiel': 'other',
  // Russian
  'Трек': 'song', 'Песня': 'song', 'Видео': 'video', 'Альбом': 'album', 'Сингл': 'album', 'Мини-альбом': 'album',
  'Исполнитель': 'artist', 'Плейлист': 'playlist', 'Выпуск': 'other', 'Эпизод': 'other', 'Подкаст': 'other',
  'Профиль': 'other', 'Радио': 'other',
  // Japanese
  '曲': 'song', '動画': 'video', 'アルバム': 'album', 'シングル': 'album', 'アーティスト': 'artist',
  'プレイリスト': 'playlist', 'エピソード': 'other', 'ポッドキャスト': 'other', 'プロフィール': 'other', 'ステーション': 'other',
  // Korean
  '노래': 'song', '동영상': 'video', '앨범': 'album', '싱글': 'album', '아티스트': 'artist', '재생목록': 'playlist',
  '에피소드': 'other', '팟캐스트': 'other', '프로필': 'other', '스테이션': 'other',
};

/// The words that come with a count (lower case).
const _countWords = {
  // English
  'view', 'views', 'plays', 'listeners', 'audience', 'subscribers', 'streams',
  // German
  'aufruf', 'aufrufe', 'wiedergabe', 'wiedergaben', 'hörer', 'zuhörer', 'publikum', 'abonnenten',
  // Spanish
  'visualización', 'visualizaciones', 'vistas', 'reproducción', 'reproducciones', 'oyentes', 'suscriptores',
  'audiencia',
  // French
  'vue', 'vues', 'lecture', 'lectures', 'écoutes', 'auditeurs', 'abonnés', 'auditoire',
  // Italian
  'visualizzazione', 'visualizzazioni', 'riproduzione', 'riproduzioni', 'ascoltatori', 'iscritti', 'pubblico',
  // Portuguese
  'visualização', 'visualizações', 'reprodução', 'reproduções', 'ouvintes', 'inscritos', 'público',
  // Polish
  'wyświetlenie', 'wyświetlenia', 'wyświetleń', 'odtworzenie', 'odtworzenia', 'odtworzeń', 'słuchaczy',
  'subskrybentów',
  // Turkish
  'görüntüleme', 'oynatma', 'dinlenme', 'dinleyici', 'abone',
  // Dutch
  'weergave', 'weergaven', 'afgespeeld', 'luisteraars', 'abonnees', 'publiek',
  // Russian
  'просмотр', 'просмотра', 'просмотров', 'прослушивание', 'прослушивания', 'прослушиваний', 'слушателей',
  'подписчиков', 'аудитория',
};

/// Japanese, Chinese and Korean put no spaces around these, so they are looked for anywhere.
const _countMarks = ['回視聴', '回再生', '視聴回数', '再生回数', 'リスナー', '登録者', '次观看', '次播放', '조회수', '재생', '청취자', '구독자'];

/// What a short word after a number makes of it ("1.2M", "1,2 Mio.", "12 mil", "4,5万").
const _sizes = {
  'k': 1e3, 'tsd': 1e3, 'tys': 1e3, 'mil': 1e3, 'тыс': 1e3, '千': 1e3, '천': 1e3,
  'm': 1e6, 'mio': 1e6, 'mln': 1e6, 'mn': 1e6, 'mi': 1e6, 'млн': 1e6,
  'b': 1e9, 'bn': 1e9, 'mrd': 1e9, 'md': 1e9, 'mld': 1e9, 'mr': 1e9, 'млрд': 1e9,
  '万': 1e4, '만': 1e4, '億': 1e8, '亿': 1e8, '억': 1e8,
};

final _digit = RegExp(r'\d');
final _gaps = RegExp(r'[\s   ]+');
final _number = RegExp(r'\d[\d.,\s   ]*');
final _edges = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);
final _turkish = RegExp('görüntüleme|oynatma|dinlenme|dinleyici|abone');

String _bare(String word) => word.replaceAll(_edges, '');

/// The size word right after a number: 'mio' in "1,2 Mio. Aufrufe", '万' in "4,5万回視聴", or ''.
String _sizeWord(String rest) {
  final r = rest.trimLeft();
  if (r.isEmpty) return '';
  final first = r.runes.first;
  if (first >= 0x2E80) {
    // Chinese, Japanese and Korean glue it to the number, one character
    final glyph = String.fromCharCode(first);
    return _sizes.containsKey(glyph) ? glyph : '';
  }
  final word = _bare(r.split(_gaps).first);
  return _sizes.containsKey(word) ? word : '';
}

/// Whether [text] is a count of plays, views, listeners or subscribers rather than a name. Names with
/// numbers in them ("50 Cent", "Blink-182", "M83", "112") are names.
bool looksLikeCount(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty || !t.contains(_digit)) return false;
  for (final mark in _countMarks) {
    if (t.contains(mark)) return true;
  }
  for (final word in t.split(_gaps)) {
    if (_countWords.contains(_bare(word))) return true;
  }
  // a number and its size, and nothing after them: "1.2M", "1,2 Mio.", "4,5万"
  final m = _number.firstMatch(t);
  if (m == null || m.start != 0) return false;
  final rest = t.substring(m.end).trim();
  final size = _sizeWord(rest);
  return size.isNotEmpty && _bare(rest.substring(rest.indexOf(size) + size.length)).isEmpty;
}

/// How many plays or views a count says (0 when it says none): 1200000 for "1.2M views" and for
/// "1,2 Mio. Aufrufe", 1234 for "1,234 views" and for "1.234 Aufrufe".
double countValue(String text) {
  final t = text.toLowerCase();
  final m = _number.firstMatch(t);
  if (m == null) return 0;
  final raw = m.group(0)!.replaceAll(_gaps, '');
  final word = _sizeWord(t.substring(m.end));
  // Turkish writes a thousand as "B" (bin), where English writes a billion so
  final size = word == 'b' && _turkish.hasMatch(t) ? 1e3 : (_sizes[word] ?? 1.0);
  if (size == 1) return double.tryParse(raw.replaceAll(RegExp('[.,]'), '')) ?? 0.0;
  // with a size word the number is short, and its one mark is the decimal point ("1,2" or "1.2")
  return (double.tryParse(raw.replaceAll(',', '.')) ?? 0.0) * size;
}

/// [artist] when it is a name; '' when it is a count that ended up where the name belongs.
String artistOrNothing(String artist) => looksLikeCount(artist) ? '' : artist;
