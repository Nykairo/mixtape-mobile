/// Reading YouTube's answers. They are deep and YouTube moves things around in them now and then, so
/// most things are searched for by name instead of walked to along a fixed path.
library;

Map<String, Object?> asMap(Object? v) => v is Map ? Map<String, Object?>.from(v) : const {};

List<Object?> asList(Object? v) => v is List ? v : const [];

/// Every object under [key] anywhere in [node] (or with [lists], every object that has a list under
/// [key]), in the order they come.
Iterable<Map<String, Object?>> findAll(Object? node, String key, {bool lists = false}) sync* {
  if (node is Map) {
    final hit = node[key];
    if (lists && hit is List) {
      yield Map<String, Object?>.from(node);
    } else if (!lists && hit is Map) {
      yield Map<String, Object?>.from(hit);
    }
    for (final v in node.values) {
      if (v is Map || v is List) yield* findAll(v, key, lists: lists);
    }
  } else if (node is List) {
    for (final v in node) {
      if (v is Map || v is List) yield* findAll(v, key, lists: lists);
    }
  }
}

/// The first object under [key] anywhere in [node], or an empty one.
Map<String, Object?> findOne(Object? node, String key) {
  for (final m in findAll(node, key)) {
    return m;
  }
  return const {};
}

/// The pieces of a text object ({runs: [{text}...]} or {simpleText}).
List<String> runsOf(Object? text) {
  final t = asMap(text);
  final runs = t['runs'];
  if (runs is List) {
    return [
      for (final r in runs)
        if (r is Map) '${r['text'] ?? ''}',
    ];
  }
  final simple = t['simpleText'];
  return simple is String ? [simple] : const [];
}

String textOf(Object? text) => runsOf(text).join();

/// The biggest picture in a thumbnail object, wherever in it the list of pictures is.
String thumbOf(Object? t) {
  for (final holder in findAll(asMap(t), 'thumbnails', lists: true)) {
    final pics = holder['thumbnails'];
    if (pics is List && pics.isNotEmpty && pics.last is Map) return '${(pics.last as Map)['url'] ?? ''}';
  }
  return '';
}

int toInt(Object? v, {int or = 0}) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? or);

bool isClock(String s) => RegExp(r'^\d{1,2}(:\d{2}){1,2}$').hasMatch(s.trim());

int clockSeconds(String s) => s.trim().split(':').fold(0, (sum, part) => sum * 60 + (int.tryParse(part) ?? 0));

/// The first text under [key] anywhere in [node] ('' when there is none).
String findText(Object? node, String key) {
  if (node is Map) {
    final hit = node[key];
    if (hit is String) return hit;
    for (final v in node.values) {
      if (v is Map || v is List) {
        final t = findText(v, key);
        if (t.isNotEmpty) return t;
      }
    }
  } else if (node is List) {
    for (final v in node) {
      final t = findText(v, key);
      if (t.isNotEmpty) return t;
    }
  }
  return '';
}

/// Lowercase letters and digits of any script, accents dropped: for telling whether two names match.
String folded(String s) {
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final plain = _accents[ch] ?? ch;
    out.write(_letter.hasMatch(plain) ? plain : ' ');
  }
  return out.toString().split(' ').where((w) => w.isNotEmpty).join(' ');
}

final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ç': 'c', 'č': 'c', 'ć': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ě': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n', 'ń': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ś': 's',
  'š': 's', 'ß': 'ss', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ý': 'y', 'ÿ': 'y', 'ž': 'z',
  'ź': 'z', 'ż': 'z', 'ł': 'l', 'ř': 'r', 'ğ': 'g', 'ı': 'i', 'ş': 's',
};
