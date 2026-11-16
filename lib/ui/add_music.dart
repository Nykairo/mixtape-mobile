/// Adding music from elsewhere: a playlist from Spotify, YouTube, YouTube Music or Deezer (or a pasted
/// list) made into a tape, and a podcast with its newest episodes. Library's + opens both, and a list's
/// link pasted into the search box comes here by itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../importer.dart';
import '../look.dart';
import '../model.dart';
import '../podcasts.dart';
import 'shell.dart';
import 'tape_page.dart';
import 'widgets.dart';

/// The + in the library: a new tape, a playlist from elsewhere, or a podcast.
Future<void> addMusic(BuildContext context, {required VoidCallback newTape}) async {
  final pick = await showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('ADD MUSIC', style: Look.cond(13.5, spacing: 2.2)),
        ),
        for (final (k, icon, title, about) in const [
          (0, Icons.add_rounded, 'New tape', 'Name it, then fill it with songs'),
          (1, Icons.playlist_add_rounded, 'Import a playlist', 'From Spotify, YouTube, YouTube Music or Deezer, or a list of songs'),
          (2, Icons.podcasts_rounded, 'Add a podcast', 'Find it by name, or paste its RSS link'),
        ])
          ListTile(
            leading: Icon(icon, color: Look.cream),
            title: Text(title, style: Look.ui(15.5, weight: FontWeight.w600)),
            subtitle: Text(about, style: Look.ui(13, color: Look.muted)),
            onTap: () => Navigator.of(sheet).pop(k),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (!context.mounted || pick == null) return;
  switch (pick) {
    case 0:
      newTape();
    case 1:
      Shell.push(const ImportPage());
    case 2:
      Shell.push(const PodcastPage());
  }
}

// ---------------------------------------------------------------- a playlist from elsewhere

class ImportPage extends StatefulWidget {
  const ImportPage({super.key, this.start = ''});

  /// A link to start with right away (pasted into the search box).
  final String start;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final _text = TextEditingController(text: widget.start);
  final _name = TextEditingController();
  bool _busy = false;
  String _trouble = '';
  (int, int) _progress = (0, 0);
  List<Track>? _found;
  List<Wanted> _missing = const [];
  String _note = '';

  @override
  void initState() {
    super.initState();
    if (widget.start.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final got = await Clipboard.getData(Clipboard.kTextPlain);
    final t = got?.text?.trim() ?? '';
    if (t.isEmpty || !mounted) return;
    setState(() => _text.text = t);
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _trouble = '';
      _found = null;
      _progress = (0, 0);
    });
    try {
      final list = await Importer.load(_text.text);
      if (!mounted) return;
      _name.text = list.name;
      setState(() => _progress = (0, list.wanted.length));
      final (found, missing) = await Importer.findAll(list.wanted, progress: (done, all) {
        if (mounted) setState(() => _progress = (done, all));
      });
      if (!mounted) return;
      setState(() {
        _found = [...list.ready, ...found];
        _missing = missing;
        _note = list.note;
      });
    } on ImportTrouble catch (e) {
      if (mounted) setState(() => _trouble = e.why);
    } on Object {
      if (mounted) setState(() => _trouble = "Couldn't read that list. Check the link and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _keep() {
    final songs = _found ?? const <Track>[];
    if (songs.isEmpty) return;
    final name = _name.text.trim().isEmpty ? 'Imported songs' : _name.text.trim();
    final tape = App.library.newTape(name, songs: songs);
    Navigator.of(context).pop();
    Shell.push(TapePage(tape: tape));
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final (done, all) = _progress;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Look.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Import a playlist', style: Look.ui(19, weight: FontWeight.w800)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
          if (found == null) ...[
            Text(
              'A link to a playlist, an album or a song from Spotify, YouTube, YouTube Music or Deezer. '
              'Or a list of songs, one per line as Artist - Title (a CSV from exportify.net works too).',
              style: Look.ui(14, color: Look.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 8,
              enabled: !_busy,
              style: Look.ui(15),
              decoration: InputDecoration(
                hintText: 'https://open.spotify.com/playlist/...',
                filled: true,
                fillColor: Look.raised,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _paste,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy ? null : _go,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Import'),
              ),
            ]),
            if (_busy) ...[
              const SizedBox(height: 22),
              LinearProgressIndicator(value: all == 0 ? null : done / all, color: Look.accent, backgroundColor: Look.raised),
              const SizedBox(height: 10),
              Text(all == 0 ? 'Reading the list…' : 'Finding the songs: $done of $all',
                  style: Look.ui(14, color: Look.muted)),
            ],
            if (_trouble.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(_trouble, style: Look.ui(14.5, color: Look.accent, height: 1.4)),
            ],
          ] else ...[
            TextField(
              controller: _name,
              style: Look.ui(20, weight: FontWeight.w800),
              decoration: const InputDecoration(labelText: 'The tape', border: InputBorder.none),
            ),
            Text(
              _missing.isEmpty
                  ? 'All ${count(found.length)} found.'
                  : '${count(found.length)} found, ${_missing.length} not: they are listed at the end.',
              style: Look.ui(14, color: Look.muted),
            ),
            if (_note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_note, style: Look.ui(13.5, color: Look.accent, height: 1.4)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              TextButton(onPressed: () => setState(() => _found = null), child: const Text('Another list')),
              const Spacer(),
              FilledButton.icon(
                onPressed: found.isEmpty ? null : _keep,
                icon: const Icon(Icons.library_add_rounded, size: 18),
                label: const Text('Make the tape'),
              ),
            ]),
            const SizedBox(height: 6),
            for (final t in found.take(300))
              SongRow(track: t, onTap: () => App.audio.playSongs(found, start: found.indexOf(t), from: _name.text)),
            if (found.length > 300)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('and ${found.length - 300} more on the tape', style: Look.ui(13.5, color: Look.muted)),
              ),
            if (_missing.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('NOT FOUND', style: Look.cond(13, spacing: 2)),
              const SizedBox(height: 6),
              for (final w in _missing)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(w.artist.isEmpty ? w.title : '${w.artist} - ${w.title}', style: Look.ui(14, color: Look.muted)),
                ),
            ],
          ],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- podcasts

class PodcastPage extends StatefulWidget {
  const PodcastPage({super.key});

  @override
  State<PodcastPage> createState() => _PodcastPageState();
}

class _PodcastPageState extends State<PodcastPage> {
  final _field = TextEditingController();
  List<Show>? _shows;
  bool _busy = false;
  String _trouble = '';

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _field.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    if (q.startsWith('http')) return _add(q, '');
    setState(() {
      _busy = true;
      _trouble = '';
    });
    try {
      final shows = await Podcasts.search(q);
      if (!mounted) return;
      setState(() {
        _shows = shows;
        if (shows.isEmpty) _trouble = 'No podcast by that name. Try other words, or paste its RSS link.';
      });
    } on PodcastTrouble catch (e) {
      if (mounted) setState(() => _trouble = e.why);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(String feed, String name) async {
    setState(() {
      _busy = true;
      _trouble = '';
    });
    try {
      final (title, episodes) = await Podcasts.episodes(feed);
      if (!mounted) return;
      final lib = App.library;
      final show = 'Podcast: ${name.isEmpty ? title : name}';
      // one tape per show: added again, the new episodes go on the one there is
      final have = lib.tapes[show];
      final Tape tape;
      if (have != null) {
        lib.addTo(have, episodes);
        tape = have;
      } else {
        tape = lib.newTape(show, songs: episodes);
      }
      Navigator.of(context).pop();
      Shell.push(TapePage(tape: tape));
    } on PodcastTrouble catch (e) {
      if (mounted) setState(() => _trouble = e.why);
    } on Object {
      if (mounted) setState(() => _trouble = "That isn't a podcast feed Mixtape can read.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shows = _shows;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Look.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Add a podcast', style: Look.ui(19, weight: FontWeight.w800)),
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _field,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              style: Look.ui(16),
              decoration: InputDecoration(
                hintText: "A podcast's name, or its RSS link",
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Look.raised,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_trouble.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_trouble, textAlign: TextAlign.center, style: Look.ui(14.5, color: Look.muted, height: 1.4)),
            ),
          Expanded(
            child: shows == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text('The newest 50 episodes go on a tape of their own, on the computer too.',
                          textAlign: TextAlign.center, style: Look.ui(14.5, color: Look.muted, height: 1.4)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: shows.length,
                    itemBuilder: (context, k) {
                      final s = shows[k];
                      return ListTile(
                        leading: Pic(s.art, size: 52, radius: 8, icon: Icons.podcasts_rounded),
                        title: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Look.ui(15.5, weight: FontWeight.w600)),
                        subtitle: Text(s.by, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
                        trailing: const Icon(Icons.add_circle_outline_rounded, color: Look.cream),
                        onTap: _busy ? null : () => _add(s.feed, s.name),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
