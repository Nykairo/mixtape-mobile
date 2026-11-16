/// Profiles: what your Mixtape Account shows friends, and how theirs look here. The same profiles as on
/// the computer (profiles.py there): a picture, or a monogram over a little cassette window in your
/// color; the name friends see and your pronouns; a few lines about you; a song of yours; a tape on
/// show; and the artists you've played most lately.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mixtape_native/mixtape_native.dart';

import '../account.dart';
import '../app.dart';
import '../look.dart';
import '../model.dart';
import '../together.dart' show shareable;
import 'pages.dart';
import 'shell.dart';
import 'widgets.dart';

const profileColors = [
  Color(0xFFFF6A1A),
  Color(0xFF4DA3FF),
  Color(0xFFE7B24A),
  Color(0xFFFF5F8F),
  Color(0xFF39D0A0),
  Color(0xFFA779FF),
  Color(0xFFEF4444),
  Color(0xFF22C1D6),
];

/// The profile's color, or one picked from the user name for those who didn't pick one.
Color profileColor(Map<Object?, Object?> p) {
  final c = '${p['color'] ?? ''}';
  if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(c)) return Color(int.parse('FF${c.substring(1)}', radix: 16));
  var seed = 0;
  for (final u in utf8.encode('${p['username'] ?? '?'}')) {
    seed = (seed * 31 + u) & 0x7FFFFFFF;
  }
  return profileColors[seed % profileColors.length];
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String nameOfProfile(Map<Object?, Object?> p) {
  final shown = '${p['display_name'] ?? ''}';
  return shown.isNotEmpty ? shown : '${p['username'] ?? ''}';
}

String _initials(Map<Object?, Object?> p) {
  final name = nameOfProfile(p).trim();
  final words = name.replaceAll(RegExp(r'[_.]'), ' ').split(' ').where((w) => w.isNotEmpty).toList();
  if (words.length > 1) return (words.first[0] + words.last[0]).toUpperCase();
  return name.isEmpty ? '?' : name.characters.first.toUpperCase();
}

/// Profile pictures read back, by account and version, a few dozen at most.
final _faces = LinkedHashMap<String, Uint8List>();

Uint8List? _face(Map<Object?, Object?> p) {
  final data = '${p['avatar'] ?? ''}';
  if (data.isEmpty || data.length > 160000) return null;
  final key = '${p['id']}:${p['updated_at']}:${data.length}';
  final had = _faces.remove(key);
  if (had != null) return _faces[key] = had;
  try {
    final bytes = base64Decode(data);
    _faces[key] = bytes;
    while (_faces.length > 24) {
      _faces.remove(_faces.keys.first);
    }
    return bytes;
  } on FormatException {
    return null;
  }
}

/// A round profile picture, or the monogram: the initials over a little cassette window with two
/// reels, on the profile's color.
class Avatar extends StatelessWidget {
  const Avatar(this.profile, {super.key, this.size = 40});

  final Map<Object?, Object?> profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = _face(profile);
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(bytes,
            width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
            errorBuilder: (context, error, stack) => _Monogram(profile, size)),
      );
    }
    return _Monogram(profile, size);
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram(this.profile, this.size);

  final Map<Object?, Object?> profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = profileColor(profile);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MonogramPainter(color),
        child: Align(
          alignment: const Alignment(0, -0.22),
          child: Text(_initials(profile),
              style: Look.ui(size * 0.36, weight: FontWeight.w900, color: Look.bg).copyWith(height: 1)),
        ),
      ),
    );
  }
}

class _MonogramPainter extends CustomPainter {
  const _MonogramPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    canvas.drawCircle(c, r, Paint()..color = color);
    // the cassette's window under the letters: a pill with two reels
    final window = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(r, size.height * 0.72), width: size.width * 0.46, height: size.height * 0.15),
        Radius.circular(size.height * 0.075));
    canvas.drawRRect(window, Paint()..color = Look.bg.withValues(alpha: 0.55));
    final reel = Paint()..color = color;
    canvas.drawCircle(Offset(r - size.width * 0.12, size.height * 0.72), size.width * 0.04, reel);
    canvas.drawCircle(Offset(r + size.width * 0.12, size.height * 0.72), size.width * 0.04, reel);
  }

  @override
  bool shouldRepaint(_MonogramPainter old) => old.color != color;
}

// ---------------------------------------------------------------- somebody's profile

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.username});

  final String username;

  /// Opens a profile in the tab that's showing; [over] a page of its own (Together), over that one.
  static void open(String username, {BuildContext? over}) {
    final page = ProfilePage(username: username);
    if (over == null) {
      Shell.push(page);
    } else {
      Navigator.of(over, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, Object?>? _p;
  String _trouble = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await App.account.card(widget.username);
      if (mounted) setState(() => _p = p);
    } on AccountError catch (e) {
      if (mounted) setState(() => _trouble = e.message);
    } on Object {
      if (mounted) setState(() => _trouble = AccountError('offline').message);
    }
  }

  bool get _mine => Account.cleanName(widget.username) == (App.account.session?.username ?? '');

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(backgroundColor: Look.bg, surfaceTintColor: Colors.transparent),
      body: SafeArea(
        top: false,
        child: p == null
            ? Center(
                child: _trouble.isEmpty
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(_trouble, textAlign: TextAlign.center, style: Look.ui(15, color: Look.muted, height: 1.4)),
                      ),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 28), children: [
                ProfileCard(p),
                const SizedBox(height: 18),
                if (_mine)
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileEditPage()));
                      if (mounted) _load();
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit your profile'),
                  )
                else ...[
                  if (p['share_listening'] != false)
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          await App.together.listenAlong('${p['username']}');
                          if (context.mounted) Navigator.of(context).maybePop();
                        } on AccountError catch (e) {
                          if (context.mounted) say(context, e.message);
                        }
                      },
                      icon: const Icon(Icons.headphones_rounded),
                      label: Text('Listen along with ${nameOfProfile(p)}'),
                    ),
                  if (App.together.room != null && App.together.canSteer) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await App.together.invite('${p['username']}');
                          if (context.mounted) say(context, 'Invited');
                        } on AccountError catch (e) {
                          if (context.mounted) say(context, e.message);
                        }
                      },
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(App.together.party ? 'Invite them to the party' : 'Invite them to the room'),
                    ),
                  ],
                ],
              ]),
      ),
    );
  }
}

/// One profile the way friends see it: the band in its color with the picture, the name and the words,
/// then the song, the tape on show and the artists. The song and the tape play when tapped.
class ProfileCard extends StatelessWidget {
  const ProfileCard(this.p, {super.key});

  final Map<String, Object?> p;

  @override
  Widget build(BuildContext context) {
    final color = profileColor(p);
    final anthem = Track.fromJson(p['anthem']);
    final show = p['showcase'] is Map ? Map<String, Object?>.from(p['showcase'] as Map) : null;
    final showSongs = [
      for (final s in show?['songs'] is List ? show!['songs'] as List : const [])
        if (Track.fromJson(s) case final Track t) t,
    ];
    final top = [
      for (final a in p['top_artists'] is List ? p['top_artists'] as List : const [])
        if ('$a'.isNotEmpty) '$a',
    ];
    final pronouns = '${p['pronouns'] ?? ''}';
    final bio = '${p['bio'] ?? ''}';
    return Container(
      decoration: BoxDecoration(color: Look.raised, borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 70,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, Color.lerp(color, Look.raised, 0.55)!]),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -38),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Look.raised, shape: BoxShape.circle),
                child: Avatar(p, size: 76),
              ),
              const SizedBox(height: 8),
              Text(nameOfProfile(p), style: Look.ui(24, weight: FontWeight.w900)),
              Text('@${p['username'] ?? ''}${pronouns.isEmpty ? '' : '  ·  $pronouns'}',
                  style: Look.ui(14, color: Look.muted)),
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(bio, style: Look.ui(15, height: 1.4)),
              ],
            ]),
          ),
        ),
        if (anthem != null) ...[
          _Label('MY SONG', color),
          SongRow(track: anthem, onTap: () => App.audio.playSongs([anthem], from: "${nameOfProfile(p)}'s song")),
        ],
        if (show != null && showSongs.isNotEmpty) ...[
          _Label('ON SHOW', color),
          InkWell(
            onTap: () => App.audio.playSongs(showSongs, from: '${show['name'] ?? ''}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Row(children: [
                SizedBox(
                  width: 130,
                  child: TapeArtPlain(
                    title: '${show['name'] ?? ''}',
                    slot: show['paper'] is num ? (show['paper'] as num).toInt() : 0,
                    design: show['design'] is Map ? Map<String, Object?>.from(show['design'] as Map) : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${show['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Look.ui(16, weight: FontWeight.w700)),
                    Text(count(show['count'] is num ? (show['count'] as num).toInt() : showSongs.length),
                        style: Look.ui(13, color: Look.muted)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.play_circle_fill_rounded, color: color, size: 22),
                      const SizedBox(width: 6),
                      Text('Play it', style: Look.ui(13.5, weight: FontWeight.w700)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ],
        if (top.isNotEmpty) ...[
          _Label('LATELY', color),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in top)
                ActionChip(
                  label: Text(a),
                  labelStyle: Look.ui(13.5, weight: FontWeight.w600),
                  backgroundColor: Look.bg,
                  side: BorderSide(color: color.withValues(alpha: 0.6)),
                  onPressed: () {
                    // back down to the tabs first, wherever the profile was opened from
                    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
                    Shell.push(SearchResultsView(query: a, filter: 'artists'));
                  },
                ),
            ]),
          ),
        ],
        if (anthem == null && show == null && top.isEmpty) const SizedBox(height: 4),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
        child: Text(text, style: Look.cond(12.5, color: color, spacing: 2.2)),
      );
}

// ---------------------------------------------------------------- yours, to change

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _name = TextEditingController();
  final _pronouns = TextEditingController();
  final _bio = TextEditingController();
  Map<String, Object?>? _p;
  String _picture = '';
  String _color = '';
  Map<String, Object?>? _anthem;
  String _show = ''; // the tape on show, by name ('' for none)
  bool _top = true;
  bool _saving = false;
  String _trouble = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _pronouns.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = App.account.session?.username ?? '';
    try {
      final p = await App.account.card(me);
      if (!mounted) return;
      setState(() {
        _p = p;
        _name.text = '${p['display_name'] ?? ''}';
        _pronouns.text = '${p['pronouns'] ?? ''}';
        _bio.text = '${p['bio'] ?? ''}';
        _picture = '${p['avatar'] ?? ''}';
        _color = '${p['color'] ?? ''}';
        _anthem = p['anthem'] is Map ? Map<String, Object?>.from(p['anthem'] as Map) : null;
        final show = p['showcase'];
        _show = show is Map ? '${show['name'] ?? ''}' : '';
        final top = p['top_artists'];
        _top = top is! List || top.isNotEmpty;
      });
    } on AccountError catch (e) {
      if (mounted) setState(() => _trouble = e.message);
    }
  }

  /// What the profile would show with what's typed and picked here.
  Map<String, Object?> _values() {
    final tape = App.library.tapes[_show];
    return {
      'display_name': _name.text,
      'pronouns': _pronouns.text,
      'bio': _bio.text,
      'color': _color,
      'avatar': _picture,
      'anthem': _anthem,
      'showcase': tape == null ? null : showcaseOf(tape),
      'top_artists': _top ? [for (final (n, _) in App.history.all.artists.take(5)) n] : const <String>[],
    };
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _trouble = '';
    });
    try {
      await App.account.saveProfile(_values());
      if (!mounted) return;
      say(context, 'Your profile is saved. Friends see it the next time they look you up.');
      Navigator.of(context).pop();
    } on AccountError catch (e) {
      if (mounted) setState(() => _trouble = e.detail == 'picture too big' ? 'That picture is too big.' : e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPicture() async {
    if (!Platform.isAndroid) {
      say(context, 'Pick your picture on the computer for now: it shows here too.');
      return;
    }
    final data = await MixtapeNative.pickPicture();
    if (data == null || !mounted) return;
    setState(() => _picture = data);
  }

  Future<void> _pickTape() async {
    final tapes = [
      for (final t in App.library.shownTapes)
        if (t.songs.any((s) => shareable(s) != null)) t,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: const Text('No tape on show'),
              onTap: () => Navigator.of(sheet).pop(''),
            ),
            for (final t in tapes)
              ListTile(
                leading: SizedBox(width: 56, child: TapeArt(tape: t, small: true)),
                title: Text(t.shownName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(count(t.songs.length)),
                onTap: () => Navigator.of(sheet).pop(t.name),
              ),
          ]),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _show = picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final preview = p == null ? null : {...p, ..._values(), 'username': p['username'], 'id': p['id'], 'updated_at': 'now'};
    final current = App.audio.current;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Look.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Your profile', style: Look.ui(19, weight: FontWeight.w800)),
        actions: [
          TextButton(onPressed: p == null || _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        top: false,
        child: p == null || preview == null
            ? Center(child: _trouble.isEmpty ? const CircularProgressIndicator() : Text(_trouble))
            : ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 32), children: [
                ProfileCard(preview),
                if (_trouble.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_trouble, style: Look.ui(14, color: Look.accent)),
                  ),
                const SectionTitle('Picture'),
                Row(children: [
                  FilledButton.tonalIcon(
                    onPressed: _pickPicture,
                    icon: const Icon(Icons.photo_rounded),
                    label: Text(_picture.isEmpty ? 'Pick a picture' : 'Another picture'),
                  ),
                  const SizedBox(width: 8),
                  if (_picture.isNotEmpty)
                    TextButton(onPressed: () => setState(() => _picture = ''), child: const Text('Use the monogram')),
                ]),
                const SectionTitle('About you'),
                TextField(
                  controller: _name,
                  maxLength: 40,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'The name friends see'),
                ),
                TextField(
                  controller: _pronouns,
                  maxLength: 24,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Pronouns'),
                ),
                TextField(
                  controller: _bio,
                  maxLength: 160,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'A few lines about you'),
                ),
                const SectionTitle('Your color'),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final c in profileColors)
                    GestureDetector(
                      onTap: () => setState(() => _color = _hex(c)),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == _hex(c) ? Look.cream : Colors.transparent, width: 3),
                        ),
                      ),
                    ),
                ]),
                const SectionTitle('Your song'),
                if (_anthem != null)
                  Row(children: [
                    Expanded(
                      child: Text('${_anthem!['title'] ?? ''}  ·  ${_anthem!['artist'] ?? ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15)),
                    ),
                    TextButton(onPressed: () => setState(() => _anthem = null), child: const Text('Take it off')),
                  ]),
                if (current != null && shareable(current) != null)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _anthem = shareable(current)),
                    icon: const Icon(Icons.music_note_rounded),
                    label: Text('Use what plays: ${current.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  )
                else if (_anthem == null)
                  Text('Play the song you want here, then come back.', style: Look.ui(14, color: Look.muted)),
                const SectionTitle('A tape on show'),
                OutlinedButton.icon(
                  onPressed: _pickTape,
                  icon: const Icon(Icons.album_rounded),
                  label: Text(_show.isEmpty ? 'Pick a tape' : App.library.tapes[_show]?.shownName ?? _show,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _top,
                  activeThumbColor: Look.accent,
                  title: Text('Show the artists I play most', style: Look.ui(15.5)),
                  subtitle: Text('Your five most played on this phone, refreshed when you save.',
                      style: Look.ui(13, color: Look.muted)),
                  onChanged: (v) => setState(() => _top = v),
                ),
              ]),
      ),
    );
  }
}

/// A tape as a profile shows it: its name, look and up to 50 of its songs that play anywhere. Photos
/// stuck on it stay home (they live in your account only).
Map<String, Object?>? showcaseOf(Tape t) {
  final shared = [
    for (final s in t.songs)
      if (shareable(s) case final Map<String, Object?> j) j,
  ].take(50).toList();
  if (shared.isEmpty) return null;
  final design = t.design;
  Map<String, Object?> look = {};
  if (design != null) {
    look = {
      for (final e in design.entries)
        if (e.key != 'items') e.key: e.value,
    };
    final items = design['items'];
    look['items'] = [
      for (final it in items is List ? items : const [])
        if (it is Map && it['kind'] != 'photo')
          {
            for (final e in it.entries)
              if (e.key != 'image') '${e.key}': e.value,
          },
    ].take(40).toList();
  }
  final name = t.name.length > 80 ? t.name.substring(0, 80) : t.name;
  return {'name': name, 'paper': t.paper ?? slotFor(t.name), 'design': look, 'songs': shared, 'count': t.songs.length};
}
