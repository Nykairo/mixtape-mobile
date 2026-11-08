/// Your tapes: the liked songs and every tape, the ones from the computer too, and the account they
/// come from.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../cassette.dart';
import '../look.dart';
import '../model.dart';
import 'sign_in.dart';
import 'tape_page.dart';
import 'widgets.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  Future<void> _newTape(BuildContext context) async {
    final name = await askText(context, title: 'New tape', hint: 'Name it', action: 'Make it');
    if (name == null || !context.mounted) return;
    final tape = App.library.newTape(name);
    Navigator.of(context).push(TapePage.of(tape));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.library,
      builder: (context, _) {
        final lib = App.library;
        final mine = [
          for (final t in lib.shownTapes)
            if (t.group == null) t,
        ];
        final grouped = [
          for (final t in lib.shownTapes)
            if (t.group != null) t,
        ];
        final width = MediaQuery.sizeOf(context).width;
        final columns = width >= 600 ? 3 : 2;
        // a tile: the cassette at its shape, and two lines of text under it
        final tile = (width - 20) / columns;
        final extent = (tile - 12) / ratio + 64 * MediaQuery.textScalerOf(context).scale(1);
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
                titleSpacing: 20,
                title: Text('Your tapes', style: Look.ui(24, weight: FontWeight.w800)),
                actions: [
                  IconButton(
                    tooltip: 'New tape',
                    icon: const Icon(Icons.add_rounded, color: Look.cream),
                    onPressed: () => _newTape(context),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
              const SliverToBoxAdapter(child: _AccountCard()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: extent,
                  ),
                  delegate: SliverChildListDelegate([
                    LikedTile(width: double.infinity, onTap: () => Navigator.of(context).push(TapePage.liked())),
                    for (final t in mine)
                      TapeTile(tape: t, width: double.infinity, onTap: () => Navigator.of(context).push(TapePage.of(t))),
                  ]),
                ),
              ),
              if (mine.isEmpty)
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
              if (grouped.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionTitle('From the computer: podcasts and YouTube lists')),
                SliverList.builder(
                  itemCount: grouped.length,
                  itemBuilder: (context, k) {
                    final t = grouped[k];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: Icon(t.group == 'Podcast' ? Icons.podcasts_rounded : Icons.smart_display_rounded,
                          color: Look.muted),
                      title: Text(t.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5)),
                      subtitle: Text('${t.group}  ·  ${t.songs.length} ${t.songs.length == 1 ? 'song' : 'songs'}',
                          style: Look.ui(13, color: Look.muted)),
                      onTap: () => Navigator.of(context).push(TapePage.of(t)),
                    );
                  },
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ]),
          ),
        );
      },
    );
  }
}

/// Signed in, and in step; or the way to sign in.
class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final lib = App.library;
    final s = App.account.session;
    final String line;
    if (s == null) {
      line = 'Sign in, and your tapes and liked songs from the computer come over.';
    } else if (lib.syncing) {
      line = 'Bringing your tapes in step…';
    } else if (lib.trouble != null) {
      line = lib.trouble!;
    } else {
      line = 'Your tapes are in step with the computer. Pull down to check again.';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Material(
        color: Look.side,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: s == null ? () => SignInPage.open(context) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Look.accent.withValues(alpha: 0.18),
                child: s == null
                    ? Icon(Icons.person_outline_rounded, color: Look.accent)
                    : Text(s.display.isEmpty ? '?' : String.fromCharCode(s.display.runes.first).toUpperCase(),
                        style: Look.ui(17, weight: FontWeight.w800, color: Look.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s == null ? 'Mixtape Account' : '${s.display}  ·  @${s.username}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(line, style: Look.ui(13, color: lib.trouble != null ? Look.accent : Look.muted, height: 1.3)),
                ]),
              ),
              if (s == null) const Icon(Icons.chevron_right_rounded, color: Look.muted),
              if (lib.syncing)
                const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Liked songs, as a tape of their own (the computer writes "don't tape over!" on its note).
class LikedTile extends StatelessWidget {
  const LikedTile({super.key, required this.onTap, this.width = 168});

  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final liked = App.library.liked;
    final seconds = liked.fold(0, (s, t) => s + t.dur);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Cassette(
              title: 'Liked songs',
              slot: 3,
              sticky: "don't tape over!",
              leftNote: tapeFor(seconds),
              rightNote: '${liked.length} ${liked.length == 1 ? 'song' : 'songs'}',
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.favorite_rounded, size: 15, color: Look.accent),
              const SizedBox(width: 5),
              Text('Liked songs', style: Look.ui(14.5, weight: FontWeight.w600)),
            ]),
            Text('${liked.length} ${liked.length == 1 ? 'song' : 'songs'}', style: Look.ui(12.5, color: Look.muted)),
          ]),
        ),
      ),
    );
  }
}
