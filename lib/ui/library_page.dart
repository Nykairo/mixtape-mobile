/// Your Library, the way Spotify lays it out: filters on top (tapes, what's on the phone, the computer's
/// podcasts and YouTube lists), sorting, a list or a grid of cassettes, Liked songs and pinned tapes
/// first, a long press for everything else. And the Mixtape Account the tapes come from.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import '../model.dart';
import 'add_music.dart';
import 'shell.dart';
import 'sign_in.dart';
import 'tape_page.dart';
import 'widgets.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _filter = ''; // '', 'phone', 'Podcast', 'YouTube'

  Future<void> _newTape() async {
    final name = await askText(context, title: 'New tape', hint: 'Name it', action: 'Make it');
    if (name == null || !mounted) return;
    final tape = App.library.newTape(name);
    Shell.push(TapePage(tape: tape));
  }

  List<Tape> _sorted(List<Tape> tapes) {
    final lib = App.library;
    final sort = App.settings.sort;
    final list = List.of(tapes);
    if (sort == 'name') {
      list.sort((a, b) => a.shownName.toLowerCase().compareTo(b.shownName.toLowerCase()));
    } else if (sort == 'songs') {
      list.sort((a, b) => b.songs.length.compareTo(a.songs.length));
    } else {
      // recents: opened lately first, then the newest
      final order = [
        for (final o in lib.opened)
          if (o['kind'] == 'tape') '${o['id']}',
      ];
      final newest = tapes.reversed.toList();
      int rank(Tape t) {
        final k = order.indexOf(t.name);
        return k >= 0 ? k : order.length + newest.indexOf(t);
      }

      list.sort((a, b) => rank(a).compareTo(rank(b)));
    }
    final pins = lib.pinned;
    list.sort((a, b) {
      final pa = pins.indexOf(a.name), pb = pins.indexOf(b.name);
      if (pa < 0 && pb < 0) return 0;
      if (pa < 0) return 1;
      if (pb < 0) return -1;
      return pa.compareTo(pb);
    });
    return list;
  }

  void _sortMenu() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('SORT BY', style: Look.cond(13.5, spacing: 2.2)),
          ),
          for (final (key, name) in const [('recent', 'Recents'), ('name', 'Name'), ('songs', 'Most songs')])
            ListTile(
              title: Text(name, style: Look.ui(15.5, weight: FontWeight.w600)),
              trailing: App.settings.sort == key ? Icon(Icons.check_rounded, color: Look.accent) : null,
              onTap: () {
                App.settings.setLibraryView(sort: key);
                Navigator.of(sheet).pop();
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([App.library, App.downloads, App.settings]),
      builder: (context, _) {
        final lib = App.library;
        final d = App.downloads;
        final s = App.account.session;
        final groups = {for (final t in lib.shownTapes) t.group}..remove(null);
        var tapes = [
          for (final t in lib.shownTapes)
            if (_filter == 'phone'
                ? d.count(t.songs).$1 > 0
                : (_filter.isEmpty ? t.group == null : t.group == _filter))
              t,
        ];
        tapes = _sorted(tapes);
        final likedSaved = d.count(lib.liked).$1;
        final showLiked = _filter.isEmpty || (_filter == 'phone' && likedSaved > 0);
        final grid = App.settings.grid;
        final width = MediaQuery.sizeOf(context).width;
        final columns = width >= 600 ? 3 : 2;
        final tile = (width - 20) / columns;
        final extent = (tile - 12) / 1.574 + 64 * MediaQuery.textScalerOf(context).scale(1);
        return Scaffold(
          body: RefreshIndicator(
            color: Look.accent,
            backgroundColor: Look.raised,
            onRefresh: () async {
              if (App.account.signedIn) {
                await lib.sync();
                if (context.mounted && lib.trouble != null) say(context, lib.trouble!);
              }
            },
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Look.bg,
                surfaceTintColor: Colors.transparent,
                titleSpacing: 16,
                title: Row(children: [
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: s == null ? () => SignInPage.open(context) : null,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Look.accent,
                      child: s == null
                          ? const Icon(Icons.person_outline_rounded, size: 18, color: Look.bg)
                          : Text(s.display.isEmpty ? '?' : String.fromCharCode(s.display.runes.first).toUpperCase(),
                              style: Look.ui(15, weight: FontWeight.w800, color: Look.bg)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Your Library', style: Look.ui(22, weight: FontWeight.w900)),
                ]),
                actions: [
                  if (lib.syncing)
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  IconButton(
                    tooltip: 'Add music',
                    icon: const Icon(Icons.add_rounded, color: Look.cream, size: 28),
                    onPressed: () => addMusic(context, newTape: _newTape),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                    children: [
                      _chip('', 'Tapes'),
                      _chip('phone', 'On the phone'),
                      for (final g in groups) _chip(g!, g == 'Podcast' ? 'Podcasts' : 'YouTube lists'),
                    ],
                  ),
                ),
              ),
              if (s == null || lib.trouble != null) const SliverToBoxAdapter(child: _AccountCard()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                  child: Row(children: [
                    TextButton.icon(
                      onPressed: _sortMenu,
                      icon: const Icon(Icons.swap_vert_rounded, size: 18),
                      label: Text(switch (App.settings.sort) { 'name' => 'Name', 'songs' => 'Most songs', _ => 'Recents' }),
                    ),
                    const Spacer(),
                    if (_filter == 'phone')
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(_size(d.bytes), style: Look.ui(13, color: Look.muted)),
                      ),
                    IconButton(
                      tooltip: grid ? 'As a list' : 'As cassettes',
                      onPressed: () => App.settings.setLibraryView(grid: !grid),
                      icon: Icon(grid ? Icons.view_list_rounded : Icons.grid_view_rounded, color: Look.muted),
                    ),
                  ]),
                ),
              ),
              if (grid)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisExtent: extent),
                    delegate: SliverChildListDelegate([
                      if (showLiked) _LikedGridTile(onTap: () => Shell.push(const TapePage.liked())),
                      for (final t in tapes)
                        GestureDetector(
                          onLongPress: () => tapeMenu(context, t),
                          child: TapeTile(tape: t, width: double.infinity, onTap: () => Shell.push(TapePage(tape: t))),
                        ),
                    ]),
                  ),
                )
              else
                SliverList.list(children: [
                  if (showLiked)
                    _Row(
                      art: const LikedArt(small: true),
                      title: 'Liked songs',
                      sub: 'Tape  ·  ${count(lib.liked.length)}',
                      pinned: true,
                      saved: likedSaved,
                      total: lib.liked.length,
                      onTap: () => Shell.push(const TapePage.liked()),
                    ),
                  for (final t in tapes)
                    _Row(
                      art: TapeArt(tape: t, small: true),
                      title: t.shownName,
                      sub: '${t.group ?? 'Tape'}  ·  ${count(t.songs.length)}',
                      pinned: lib.isPinned(t.name),
                      saved: d.count(t.songs).$1,
                      total: d.count(t.songs).$2,
                      onTap: () => Shell.push(TapePage(tape: t)),
                      onLong: () => tapeMenu(context, t),
                    ),
                ]),
              if (tapes.isEmpty && _filter.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Text(
                      App.account.signedIn
                          ? 'No tapes yet. Make one with +, or on the computer: they come over by themselves.'
                          : 'No tapes yet. Make one with +, or sign in and the tapes from your computer come over.',
                      style: Look.ui(14.5, color: Look.muted, height: 1.4),
                    ),
                  ),
                ),
              if (_filter == 'phone' && d.all.isNotEmpty) ...[
                SliverToBoxAdapter(child: SectionTitle('Songs on the phone', over: '${d.all.length} songs')),
                SliverList.builder(
                  itemCount: d.all.length,
                  itemBuilder: (context, k) => NowPlayingBuilder(
                    builder: (context, item, playing) => SongRow(
                      track: d.all[k].track,
                      current: item?.id == d.all[k].track.id,
                      playing: playing,
                      onTap: () => App.audio.playSongs([for (final x in d.all) x.track], start: k, from: 'On the phone'),
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
            ]),
          ),
        );
      },
    );
  }

  Widget _chip(String key, String name) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(name),
          selected: _filter == key,
          showCheckmark: false,
          labelStyle: Look.ui(13.5, weight: FontWeight.w600, color: _filter == key ? Look.bg : Look.cream),
          selectedColor: Look.cream,
          backgroundColor: Look.raised,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onSelected: (_) => setState(() => _filter = _filter == key && key.isNotEmpty ? '' : key),
        ),
      );

  static String _size(int bytes) {
    if (bytes < 1 << 20) return '${(bytes / 1024).round()} KB';
    if (bytes < 1 << 30) return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
    return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.art,
    required this.title,
    required this.sub,
    required this.onTap,
    this.onLong,
    this.pinned = false,
    this.saved = 0,
    this.total = 0,
  });

  final Widget art;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final VoidCallback? onLong;
  final bool pinned;
  final int saved;
  final int total;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLong,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Row(children: [
          SizedBox(width: 76, child: art),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(children: [
                if (pinned) ...[
                  Transform.rotate(angle: 0.6, child: Icon(Icons.push_pin_rounded, size: 14, color: Look.accent)),
                  const SizedBox(width: 5),
                ],
                if (saved > 0) ...[
                  Icon(saved >= total ? Icons.arrow_circle_down_rounded : Icons.downloading_rounded,
                      size: 14, color: Look.accent),
                  const SizedBox(width: 5),
                ],
                Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _LikedGridTile extends StatelessWidget {
  const _LikedGridTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LikedArt(),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.favorite_rounded, size: 15, color: Look.accent),
            const SizedBox(width: 5),
            Text('Liked songs', style: Look.ui(14.5, weight: FontWeight.w600)),
          ]),
          Text(count(App.library.liked.length), style: Look.ui(12.5, color: Look.muted)),
        ]),
      ),
    );
  }
}

/// Signed out, or the account has trouble: the way in, or what's wrong.
class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final lib = App.library;
    final s = App.account.session;
    final line = s == null ? 'Sign in, and your tapes and liked songs from the computer come over.' : (lib.trouble ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Material(
        color: Look.side,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: s == null ? () => SignInPage.open(context) : lib.sync,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              Icon(s == null ? Icons.person_outline_rounded : Icons.sync_problem_rounded, color: Look.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s == null ? 'Mixtape Account' : 'Not in step', style: Look.ui(15, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(line, style: Look.ui(13, color: Look.muted, height: 1.3)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Look.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
