/// The tape studio on the phone: the shell, the label, the reels and the sticky note, picked from the
/// same materials as on the computer (decor.py there), with the cassette changing as you pick. What the
/// computer stuck on the tape (stickers, photos, doodles) stays on it; the changes go back to the account.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../cassette.dart';
import '../look.dart';
import '../model.dart';
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

class _StudioPageState extends State<StudioPage> {
  late final Map<String, Object?> _d = {
    for (final e in (widget.tape.design ?? const <String, Object?>{}).entries)
      if (!const {'items', 'layer', 'paper'}.contains(e.key)) e.key: e.value,
  };
  late int _paper = widget.tape.design?['paper'] is int
      ? widget.tape.design!['paper'] as int
      : (widget.tape.paper ?? slotFor(widget.tape.name));
  late final _note = TextEditingController(text: widget.tape.note);
  bool _changed = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _set(String key, Object? value) => setState(() {
        _changed = true;
        if (value == null) {
          _d.remove(key);
        } else {
          _d[key] = value;
        }
      });

  void _save() {
    final lib = App.library;
    if (_changed) lib.setDesign(widget.tape, Map.of(_d), paper: _paper);
    if (_note.text.trim() != widget.tape.note) lib.setNote(widget.tape, _note.text);
    Navigator.of(context).pop();
    if (_changed) say(context, App.account.signedIn ? 'Decorated, on the computer too in a moment' : 'Decorated');
  }

  @override
  Widget build(BuildContext context) {
    final tape = widget.tape;
    final preview = {..._d, if (tape.design?['layer'] != null) 'layer': tape.design!['layer']};
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Look.bg,
          surfaceTintColor: Colors.transparent,
          title: Text('Tape studio', style: Look.ui(19, weight: FontWeight.w800)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton(onPressed: _save, child: const Text('Done')),
            ),
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 8, 36, 14),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _note,
              builder: (context, note, _) => Cassette(
                title: tape.shownName,
                slot: _paper,
                design: preview,
                layer: App.library.layerOf(tape),
                sticky: note.text,
                leftNote: tapeFor(tape.seconds),
                rightNote: count(tape.songs.length),
                playing: true,
              ),
            ),
          ),
          TabBar(
            indicatorColor: Look.accent,
            labelColor: Look.cream,
            unselectedLabelColor: Look.muted,
            dividerColor: Look.edge,
            labelStyle: Look.cond(14, spacing: 1.6),
            tabs: const [Tab(text: 'SHELL'), Tab(text: 'LABEL'), Tab(text: 'REELS'), Tab(text: 'NOTE')],
          ),
          Expanded(
            child: TabBarView(children: [
              ListView(padding: const EdgeInsets.all(16), children: [
                _Heading('Color'),
                _Swatches([
                  for (final (k, name, c) in _shells)
                    _Swatch(c, name, (_d['shell'] ?? 'black') == k, () => _set('shell', k == 'black' ? null : k),
                        see: k == 'clear' || k == 'smoke'),
                ]),
                _Heading('Finish'),
                _Choices([
                  for (final (k, name) in _finishes)
                    (name, (_d['finish'] ?? 'matte') == k, () => _set('finish', k == 'matte' ? null : k)),
                ]),
                _Heading('Screws'),
                _Swatches([
                  for (final (k, name, c) in _screws) _Swatch(c, name, _d['screws'] == k, () => _set('screws', k)),
                  _Swatch(Look.raised, 'None', _d['screws'] == 'none', () => _set('screws', 'none'), none: true),
                ]),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                _Heading('Paper'),
                _Swatches([
                  for (var k = 0; k < papers.length; k++)
                    _PaperSwatch(k, _paper == k, () => setState(() {
                          _paper = k;
                          _changed = true;
                        })),
                ]),
                _Heading('Stripes'),
                _Choices([
                  for (final (k, name) in _stripes)
                    (name, (_d['stripes'] ?? 'classic') == k, () => _set('stripes', k == 'classic' ? null : k)),
                ]),
                _Heading('Lettering'),
                _Choices([
                  for (final (k, name) in _pens) (name, (_d['pen'] ?? 'hand') == k, () => _set('pen', k == 'hand' ? null : k)),
                ]),
                _Heading('Ink'),
                _Swatches([
                  _Swatch(paperFor(_paper).$3, "The paper's own", _d['ink'] == null, () => _set('ink', null)),
                  for (final (k, name, c) in _inks) _Swatch(c, name, _d['ink'] == k, () => _set('ink', k)),
                ]),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                _Heading('Hubs'),
                _Swatches([
                  _Swatch(Look.raised, 'As the shell', _d['hub'] == null, () => _set('hub', null), none: true),
                  for (final (k, name, c) in _hubs) _Swatch(c, name, _d['hub'] == k, () => _set('hub', k)),
                ]),
                _Heading('Tape'),
                _Swatches([
                  for (final (k, name, c) in _tapes)
                    _Swatch(c, name, (_d['tape'] ?? 'brown') == k, () => _set('tape', k == 'brown' ? null : k)),
                ]),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                _Heading('What it says'),
                TextField(
                  controller: _note,
                  maxLength: 28,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'A few words for the corner'),
                ),
                _Heading('Note color'),
                _Swatches([
                  _Swatch(Look.raised, 'As the paper goes', _d['corner_color'] == null, () => _set('corner_color', null), none: true),
                  for (final (k, c) in _notes) _Swatch(c, k, _d['corner_color'] == k, () => _set('corner_color', k)),
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
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 10),
        child: Text(text.toUpperCase(), style: Look.cond(13, spacing: 2)),
      );
}

class _Swatches extends StatelessWidget {
  const _Swatches(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 12, runSpacing: 12, children: children);
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color, this.name, this.on, this.onTap, {this.see = false, this.none = false});

  final Color color;
  final String name;
  final bool on;
  final VoidCallback onTap;
  final bool see;
  final bool none;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: see ? color.withValues(alpha: 0.5) : color,
            border: Border.all(color: on ? Look.accent : Look.edge, width: on ? 3 : 1.4),
            boxShadow: on ? [BoxShadow(color: Look.accent.withValues(alpha: 0.4), blurRadius: 10)] : null,
          ),
          child: none ? const Icon(Icons.block_rounded, size: 18, color: Look.muted) : null,
        ),
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

class _Choices extends StatelessWidget {
  const _Choices(this.items);

  final List<(String, bool, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (name, on, tap) in items)
        ChoiceChip(
          label: Text(name),
          selected: on,
          showCheckmark: false,
          labelStyle: Look.ui(13.5, weight: FontWeight.w600, color: on ? Look.bg : Look.cream),
          selectedColor: Look.cream,
          backgroundColor: Look.raised,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onSelected: (_) => tap(),
        ),
    ]);
  }
}
