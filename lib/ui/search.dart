/// Search: songs on YouTube Music, the way its app lists them under Songs.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import '../model.dart';
import '../youtube.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _typing;
  List<Track> _found = const [];
  String _asked = '';
  String _shown = '';
  bool _busy = false;
  String? _trouble;

  @override
  void dispose() {
    _typing?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 550), () => _search(text));
  }

  Future<void> _search(String text) async {
    final q = text.trim();
    _typing?.cancel();
    if (q.isEmpty || q == _shown || q == _asked) return;
    _asked = q;
    setState(() {
      _busy = true;
      _trouble = null;
    });
    try {
      final got = await YouTube.search(q);
      if (!mounted || _asked != q) return; // a newer search is on its way
      setState(() {
        _found = [for (final m in got) Track.fromYouTube(m)];
        _shown = q;
      });
    } on YouTubeError catch (e) {
      if (!mounted || _asked != q) return;
      setState(() => _trouble = e.why == 'network'
          ? "Can't reach YouTube. Check the internet connection."
          : e.why == 'busy'
              ? 'YouTube asks to slow down for a moment. Try again in a minute.'
              : "YouTube didn't answer that search. Try again.");
    } finally {
      if (mounted && _asked == q) {
        setState(() => _busy = false);
        _asked = '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, top + 14, 16, 6),
          child: TextField(
            controller: _field,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onChanged: _typed,
            onSubmitted: _search,
            style: Look.ui(16),
            decoration: InputDecoration(
              hintText: 'Songs, artists, a line you remember',
              prefixIcon: const Icon(Icons.search_rounded, color: Look.muted),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _field,
                builder: (context, v, _) => v.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded, color: Look.muted),
                        onPressed: () {
                          _field.clear();
                          _typing?.cancel();
                          setState(() {
                            _found = const [];
                            _shown = '';
                            _trouble = null;
                          });
                          _focus.requestFocus();
                        },
                      ),
              ),
            ),
          ),
        ),
        SizedBox(height: 2, child: _busy ? const LinearProgressIndicator(minHeight: 2) : null),
        Expanded(child: _results()),
      ]),
    );
  }

  Widget _results() {
    if (_trouble != null) {
      return _Quiet(icon: Icons.wifi_off_rounded, text: _trouble!);
    }
    if (_found.isEmpty) {
      return _shown.isEmpty
          ? const _Quiet(icon: Icons.graphic_eq_rounded, text: 'Find a song. Playing it plays songs like it after.')
          : _Quiet(icon: Icons.search_off_rounded, text: 'Nothing on YouTube Music for "$_shown".');
    }
    return NowPlayingBuilder(
      builder: (context, item, playing) => ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: _found.length,
        itemBuilder: (context, k) => SongRow(
          track: _found[k],
          current: item?.id == _found[k].id,
          playing: playing,
          // the song, and then songs like it (the queue keeps going by itself)
          onTap: () => App.audio.playSongs([_found[k]], from: 'Search: $_shown'),
        ),
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 42, color: Look.faint),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: Look.ui(15, color: Look.muted, height: 1.4)),
        ]),
      ),
    );
  }
}
