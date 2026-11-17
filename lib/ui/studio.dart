/// The tape studio on the phone: the shell, the label, the reels and the sticky note, picked from the
/// same materials as on the computer (decor.py there), with the cassette changing as you pick, and
/// everything stuck and drawn on it (see decorate.dart). The changes go back to the account, so the
/// computer gets them too.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../cassette.dart';
import '../decor.dart';
import '../look.dart';
import '../model.dart';
import 'decorate.dart';
import 'widgets.dart';

const _shells = [
  ('black', 'Black', Color(0xFF2E2621)),
  ('smoke', 'Smoke', Color(0xFF4A4442)),
  ('clear', 'Clear', Color(0xFFCDDBE4)),
  ('white', 'White', Color(0xFFE8E3D8)),
  ('red', 'Red', Color(0xFFB2342A)),
  ('orange', 'Orange', Color(0xFFD9692A)),
  ('yellow', 'Yellow', Color(0xFFE2B33B)),
  ('mint', 'Mint', Color(0xFF56B190)),
  ('blue', 'Blue', Color(0xFF335F9E)),
  ('purple', 'Purple', Color(0xFF684A9C)),
  ('pink', 'Pink', Color(0xFFDD86A4)),
];
const _finishes = [('matte', 'Matte'), ('gloss', 'Glossy'), ('glitter', 'Glitter')];
const _screws = [('silver', 'Silver', Color(0xFFB9B4AC)), ('gold', 'Gold', Color(0xFFD6B25E)), ('black', 'Black', Color(0xFF26221F))];
const _stripes = [('classic', 'Classic'), ('band', 'One band'), ('lines', 'Thin lines'), ('fade', 'Sunset'), ('none', 'None')];
const _pens = [('hand', 'Handwriting'), ('marker', 'Marker'), ('type', 'Typewriter'), ('print', 'Printed')];
const _inks = [
  ('blue', 'Ballpoint', Color(0xFF25428E)),
  ('black', 'Marker', Color(0xFF1F1A16)),
  ('red', 'Red pen', Color(0xFFB3261E)),
  ('green', 'Green pen', Color(0xFF1F6B45)),
  ('purple', 'Purple pen', Color(0xFF5B2A86)),
  ('white', 'Paint pen', Color(0xFFF6F1E7)),
];
const _hubs = [
  ('white', 'White', Color(0xFFECE4D4)),
  ('black', 'Black', Color(0xFF36302B)),
  ('red', 'Red', Color(0xFFC9392E)),
  ('blue', 'Blue', Color(0xFF3D6FD1)),
  ('gold', 'Gold', Color(0xFFD9AE4F)),
  ('mint', 'Mint', Color(0xFF5CC5A2)),
];
const _tapes = [
  ('brown', 'Brown', Color(0xFF3B2618)),
  ('black', 'Black', Color(0xFF18181B)),
  ('chrome', 'Chrome', Color(0xFF6B6E78)),
  ('gold', 'Gold', Color(0xFF7D5C22)),
  ('red', 'Red', Color(0xFF5E1B17)),
];
const _notes = [
  ('yellow', Color(0xFFF8E17A)),
  ('pink', Color(0xFFF7B9C9)),
  ('blue', Color(0xFFBCDCF5)),
  ('green', Color(0xFFC8EAB2)),
  ('orange', Color(0xFFFFC68E)),
  ('lilac', Color(0xFFD8C7F3)),
];

class StudioPage extends StatefulWidget {
  const StudioPage({super.key, required this.tape});

  final Tape tape;

  static Future<void> open(BuildContext context, Tape tape) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute<void>(builder: (_) => StudioPage(tape: tape)));

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> with SingleTickerProviderStateMixin {
  late final Map<String, Object?> _d = {
    for (final e in (widget.tape.design ?? const <String, Object?>{}).entries)
      if (!const {'items', 'layer', 'paper'}.contains(e.key)) e.key: e.value,
  };
  late int _paper = widget.tape.design?['paper'] is int
      ? widget.tape.design!['paper'] as int
      : (widget.tape.paper ?? slotFor(widget.tape.name));
  late final _note = TextEditingController(text: widget.tape.note);
  late final _tabs = TabController(length: 5, vsync: this);
  late final _decor = Decorations(cleanItems(widget.tape.design?['items']));
  late final String _startItems, _startLook; // what the tape had, to know what changed

  // undo and redo: the whole studio as it was after each finished change
  final _history = <String>[];
  int _at = 0;
  late String _saved; // what the tape has: anything else is lost when leaving without Done
  Timer? _typing;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startItems = jsonEncode(_decor.items);
    _startLook = _look();
    _saved = _snapshot();
    _history.add(_saved);
    _decor.onCommit = _commit;
    _note.addListener(_typed);
    StickerSheet.load().then((_) {
      if (mounted) _decor.refresh();
    }, onError: (Object _) {});
    _showPictures();
  }

  @override
  void dispose() {
    _typing?.cancel();
    _note.dispose();
    _tabs.dispose();
    _decor.dispose();
    super.dispose();
  }

  String _look() => jsonEncode({'d': _d, 'paper': _paper});

  String _snapshot() => jsonEncode({'d': _d, 'paper': _paper, 'note': _note.text, 'items': _decor.items});

  bool get _dirty => _history[_at] != _saved || (_typing?.isActive ?? false);

  /// A change is finished: it becomes a step undo can go back to.
  void _commit() {
    _typing?.cancel();
    final now = _snapshot();
    if (now != _history[_at]) {
      _history.removeRange(_at + 1, _history.length);
      _history.add(now);
      if (_history.length > 80) _history.removeAt(0);
      _at = _history.length - 1;
    }
    if (mounted) setState(() {});
  }

  /// The note's words count as a step once the typing stops for a moment.
  void _typed() {
    final was = _typing?.isActive ?? false;
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 700), _commit);
    if (!was && mounted) setState(() {}); // something to lose now: leaving asks first
  }

  void _restore(String snap) {
    final j = jsonDecode(snap) as Map<String, Object?>;
    _note.removeListener(_typed);
    setState(() {
      _d
        ..clear()
        ..addAll(Map<String, Object?>.from(j['d'] as Map));
      _paper = (j['paper'] as num).toInt();
      _note.text = '${j['note'] ?? ''}';
    });
    _note.addListener(_typed);
    _decor.restore([for (final it in j['items'] as List) Map<String, Object?>.from(it as Map)]);
  }

  void _undo() {
    _commit(); // what was typed a moment ago counts as a step too
    if (_at == 0) return;
    _at--;
    _restore(_history[_at]);
  }

  void _redo() {
    if (_at >= _history.length - 1) return;
    _at++;
    _restore(_history[_at]);
  }

  void _set(String key, Object? value) {
    setState(() {
      if (value == null) {
        _d.remove(key);
      } else {
        _d[key] = value;
      }
    });
    _commit();
  }

  /// The photos on the tape: from the phone, or from the account when the computer stuck them on.
  Future<void> _showPictures() async {
    final names = picturesOf(_decor.items);
    if (names.isEmpty) return;
    await App.library.fetchPictures(names);
    for (final n in names) {
      if (!mounted) return;
      await _decor.show(n);
    }
  }

  bool _noteShows() => _note.text.trim().isNotEmpty && _d['corner_hidden'] != true;

  /// A tap on the tape that found nothing stuck on it: on the corner note, it goes to the note.
  void _tapped(Offset pos, Geo g) {
    if (!_noteShows()) return;
    final (c, side, tilt) = g.sticky(_paper);
    final a = -tilt * pi / 180;
    final d = pos - c;
    final x = d.dx * cos(a) - d.dy * sin(a), y = d.dx * sin(a) + d.dy * cos(a);
    if (x.abs() <= side / 2 && y.abs() <= side / 2) _tabs.animateTo(4);
  }

  Future<void> _save() async {
    if (_saving) return;
    _commit();
    final lib = App.library;
    final tape = widget.tape;
    final items = cleanItems(_decor.items);
    final stuck = jsonEncode(items) != _startItems;
    final looked = _look() != _startLook;
    if (stuck) {
      setState(() => _saving = true);
      String? layer;
      try {
        await _showPictures(); // a last chance for photos still on their way
        final png = await layerPng(items, pictures: _decor.pictures);
        if (png != null) layer = await lib.keepLayer(png);
      } on Object {
        layer = null; // the phones show the tape without them until it's drawn again
      }
      if (!mounted) return;
      lib.setDesign(tape, Map.of(_d), paper: _paper, items: items, layer: layer);
    } else if (looked) {
      lib.setDesign(tape, Map.of(_d), paper: _paper);
    }
    if (_note.text.trim() != tape.note) lib.setNote(tape, _note.text);
    _saved = _history[_at];
    Navigator.of(context).pop();
    if (stuck || looked) say(context, App.account.signedIn ? 'Decorated, on the computer too in a moment' : 'Decorated');
  }

  /// Back: first lets go of what's in hand, then stops the pen, and only then leaves (asking first
  /// when something would be lost).
  Future<void> _back() async {
    if (_saving) return;
    if (_decor.current != null) {
      _decor.select(-1);
      return;
    }
    if (_decor.pen) {
      _decor.setPen(false);
      return;
    }
    _commit();
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialog) => AlertDialog(
        backgroundColor: Look.side,
        title: Text('Leave without saving?', style: Look.ui(19, weight: FontWeight.w800)),
        content: Text('The changes to this tape go away. Done keeps them.', style: Look.ui(15, color: Look.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Keep working')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Leave')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tape = widget.tape;
    final page = Scaffold(
      appBar: AppBar(
        backgroundColor: Look.bg,
        surfaceTintColor: Colors.transparent,
        // on a narrow phone the name shrinks a little rather than losing its end to undo and redo
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Tape studio', style: Look.ui(19, weight: FontWeight.w800)),
        ),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _at > 0 ? _undo : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: _at < _history.length - 1 ? _redo : null,
            icon: const Icon(Icons.redo_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 10),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : const Text('Done'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          LayoutBuilder(builder: (context, box) {
            // the cassette across the phone, with room around it for the handles; on a tablet or a
            // phone on its side, small enough to leave room for the panel under it
            final screen = MediaQuery.sizeOf(context);
            final cw = min(box.maxWidth - 72, min(560.0, screen.height * 0.4 * ratio));
            final spot = Rect.fromLTWH((box.maxWidth - cw) / 2, 8, cw, cw / ratio);
            return SizedBox(
              height: spot.bottom + 14,
              child: RepaintBoundary(
                child: DecorCanvas(
                  decor: _decor,
                  box: spot,
                  onPicked: () => _tabs.animateTo(0),
                  onWrite: (k) => writeOn(context, _decor, k),
                  onTapElse: _tapped,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _note,
                    builder: (context, note, _) => Cassette(
                      title: tape.shownName,
                      slot: _paper,
                      design: Map.of(_d),
                      sticky: note.text,
                      leftNote: tapeFor(tape.seconds),
                      rightNote: count(tape.songs.length),
                      playing: true,
                    ),
                  ),
                ),
              ),
            );
          }),
          TabBar(
            controller: _tabs,
            indicatorColor: Look.accent,
            labelColor: Look.cream,
            unselectedLabelColor: Look.muted,
            dividerColor: Look.edge,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: Look.cond(14, spacing: 1.6),
            tabs: const [Tab(text: 'DECOR'), Tab(text: 'SHELL'), Tab(text: 'LABEL'), Tab(text: 'REELS'), Tab(text: 'NOTE')],
          ),
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              DecorPanel(decor: _decor, noteShows: _noteShows, onUndo: _undo),
              ListView(padding: const EdgeInsets.all(16), children: [
                const PanelHeading('Color'),
                Swatches([
                  for (final (k, name, c) in _shells)
                    Swatch(c, name, (_d['shell'] ?? 'black') == k, () => _set('shell', k == 'black' ? null : k),
                        see: k == 'clear' || k == 'smoke'),
                ]),
                const PanelHeading('Finish'),
                Choices([
                  for (final (k, name) in _finishes)
                    (name, (_d['finish'] ?? 'matte') == k, () => _set('finish', k == 'matte' ? null : k)),
                ]),
                const PanelHeading('Screws'),
                Swatches([
                  for (final (k, name, c) in _screws) Swatch(c, name, _d['screws'] == k, () => _set('screws', k)),
                  Swatch(Look.raised, 'None', _d['screws'] == 'none', () => _set('screws', 'none'), none: true),
                ]),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                const PanelHeading('Paper'),
                Swatches([
                  for (var k = 0; k < papers.length; k++)
                    _PaperSwatch(k, _paper == k, () {
                      setState(() => _paper = k);
                      _commit();
                    }),
                ]),
                const PanelHeading('Stripes'),
                Choices([
                  for (final (k, name) in _stripes)
                    (name, (_d['stripes'] ?? 'classic') == k, () => _set('stripes', k == 'classic' ? null : k)),
                ]),
                const PanelHeading('Lettering'),
                Choices([
                  for (final (k, name) in _pens) (name, (_d['pen'] ?? 'hand') == k, () => _set('pen', k == 'hand' ? null : k)),
                ]),
                const PanelHeading('Ink'),
                Swatches([
                  Swatch(paperFor(_paper).$3, "The paper's own", _d['ink'] == null, () => _set('ink', null)),
                  for (final (k, name, c) in _inks) Swatch(c, name, _d['ink'] == k, () => _set('ink', k)),
                ]),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                const PanelHeading('Hubs'),
                Swatches([
                  Swatch(Look.raised, 'As the shell', _d['hub'] == null, () => _set('hub', null), none: true),
                  for (final (k, name, c) in _hubs) Swatch(c, name, _d['hub'] == k, () => _set('hub', k)),
                ]),
                const PanelHeading('Tape'),
                Swatches([
                  for (final (k, name, c) in _tapes)
                    Swatch(c, name, (_d['tape'] ?? 'brown') == k, () => _set('tape', k == 'brown' ? null : k)),
                ]),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                const PanelHeading('What it says'),
                TextField(
                  controller: _note,
                  maxLength: 28,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'A few words for the corner'),
                  onSubmitted: (_) => _commit(),
                ),
                const PanelHeading('Note color'),
                Swatches([
                  Swatch(Look.raised, 'As the paper goes', _d['corner_color'] == null, () => _set('corner_color', null),
                      none: true),
                  for (final (k, c) in _notes) Swatch(c, k, _d['corner_color'] == k, () => _set('corner_color', k)),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _d['corner_hidden'] == true,
                  activeThumbColor: Look.accent,
                  title: Text('No sticky note', style: Look.ui(15.5)),
                  onChanged: (on) => _set('corner_hidden', on ? true : null),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
    // back lets go of the picked thing or the pen first, so it waits for those too
    return ListenableBuilder(
      listenable: _decor,
      child: page,
      builder: (context, child) => PopScope(
        canPop: !_saving && !_dirty && _decor.current == null && !_decor.pen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: child!,
      ),
    );
  }
}

class _PaperSwatch extends StatelessWidget {
  const _PaperSwatch(this.slot, this.on, this.onTap);

  final int slot;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (paper, stripes, ink) = paperFor(slot);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 62,
        height: 42,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: on ? Look.accent : Look.edge, width: on ? 3 : 1),
        ),
        child: Column(children: [
          const SizedBox(height: 7),
          Text('Aa', style: Look.hand(15, color: ink)),
          const Spacer(),
          for (final c in stripes.take(3)) Container(height: 3, color: c),
        ]),
      ),
    );
  }
}
