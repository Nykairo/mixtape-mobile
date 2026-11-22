/// What comes down to the phone: the song coming now and how far it is, the songs waiting their turn
/// (one can go first, any can stay off), the ones that wouldn't come, and what's on the phone already.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import '../model.dart';
import 'pages.dart';
import 'settings_page.dart' show sizeWords;
import 'shell.dart';
import 'widgets.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  static void open() => Shell.push(const DownloadsPage());

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.downloads,
      builder: (context, _) {
        final d = App.downloads;
        final now = d.current;
        final waiting = d.waiting;
        final failed = d.didntCome;
        final saved = d.all.length;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Look.bg,
            surfaceTintColor: Colors.transparent,
            title: Text('Downloads', style: Look.ui(20, weight: FontWeight.w800)),
          ),
          body: CustomScrollView(slivers: [
            if (now == null && waiting.isEmpty && failed.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
                  child: Text('Nothing is coming down right now. The arrow on a tape, an album or a song saves it '
                      'for when there is no internet.',
                      style: Look.ui(15, color: Look.muted, height: 1.4)),
                ),
              ),
            if (now != null) ...[
              const SliverToBoxAdapter(child: SectionTitle('Coming down now')),
              SliverToBoxAdapter(child: _Now(now)),
            ],
            if (waiting.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionTitle(
                  'Waiting their turn',
                  over: '${waiting.length} ${waiting.length == 1 ? 'song' : 'songs'}',
                  trailing: TextButton(onPressed: () => d.cancel(waiting), child: const Text('Stop them all')),
                ),
              ),
              SliverList.builder(
                itemCount: waiting.length,
                itemBuilder: (context, k) => _Waiting(waiting[k], first: k == 0),
              ),
            ],
            if (failed.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionTitle(
                  "Didn't come",
                  over: '${failed.length} ${failed.length == 1 ? 'song' : 'songs'}',
                  trailing: TextButton(onPressed: d.retry, child: const Text('Try again')),
                ),
              ),
              SliverList.builder(
                itemCount: failed.length,
                itemBuilder: (context, k) => _Row(
                  failed[k],
                  note: 'YouTube held it back. Try again later.',
                  action: IconButton(
                    tooltip: 'Forget it',
                    icon: const Icon(Icons.close_rounded, color: Look.muted),
                    onPressed: () => d.forget(failed[k]),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextButton(onPressed: d.forgetFailed, child: const Text('Forget them all')),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SectionTitle('On this phone')),
            SliverToBoxAdapter(
              child: ListTile(
                leading: const Icon(Icons.download_done_rounded, color: Look.muted),
                title: Text(saved == 0 ? 'Nothing saved yet' : '$saved ${saved == 1 ? 'song' : 'songs'}, ${sizeWords(d.bytes)}',
                    style: Look.ui(15.5)),
                subtitle: saved == 0
                    ? null
                    : Text('They play without the internet.', style: Look.ui(13, color: Look.muted)),
                trailing: saved == 0 ? null : const Icon(Icons.chevron_right_rounded, color: Look.muted),
                onTap: saved == 0
                    ? null
                    : () => Shell.push(MixView(
                          title: 'On this phone',
                          blurb: 'no internet needed',
                          songs: [for (final x in d.all) x.track],
                          slot: 3,
                        )),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ]),
        );
      },
    );
  }
}

/// The song coming down: its cover, a bar of how far it is, how much of how much and how fast.
class _Now extends StatelessWidget {
  const _Now(this.track);

  final Track track;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: App.downloads.ticks,
        builder: (context, _, __) => _card(),
      );

  Widget _card() {
    final d = App.downloads;
    final mb = d.size > 0 ? '${sizeWords(d.got)} of ${sizeWords(d.size)}' : 'Starting';
    final fast = d.speed > 0 ? '  ·  ${sizeWords(d.speed.round())}/s' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Look.raised, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Cover(track, size: 56, radius: 8),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track.title.isEmpty ? 'Untitled' : track.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5, weight: FontWeight.w700)),
              Text(track.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: d.size > 0 ? d.progress.clamp(0.0, 1.0) : null,
                  minHeight: 5,
                  backgroundColor: Look.bg,
                  color: Look.accent,
                ),
              ),
              const SizedBox(height: 6),
              Text('$mb$fast', style: Look.ui(12, color: Look.muted)),
            ]),
          ),
          IconButton(
            tooltip: 'Stop this one',
            icon: const Icon(Icons.close_rounded, color: Look.muted),
            onPressed: () => d.cancel([track]),
          ),
        ]),
      ),
    );
  }
}

/// A song waiting its turn: it can go first, or stay off the phone.
class _Waiting extends StatelessWidget {
  const _Waiting(this.track, {required this.first});

  final Track track;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return _Row(
      track,
      note: first ? 'Next' : '',
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!first)
          IconButton(
            tooltip: 'Save it next',
            icon: const Icon(Icons.vertical_align_top_rounded, color: Look.muted),
            onPressed: () => App.downloads.sooner(track),
          ),
        IconButton(
          tooltip: "Don't save it",
          icon: const Icon(Icons.close_rounded, color: Look.muted),
          onPressed: () => App.downloads.cancel([track]),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.track, {required this.note, required this.action});

  final Track track;
  final String note;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final sub = [track.artist, if (note.isNotEmpty) note].where((s) => s.isNotEmpty).join('  ·  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      child: Row(children: [
        Cover(track, size: 44, radius: 6),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(track.title.isEmpty ? 'Untitled' : track.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15, weight: FontWeight.w600)),
            if (sub.isNotEmpty)
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
          ]),
        ),
        action,
      ]),
    );
  }
}

/// A small bar that says what's coming down, for the top of the library: tap it for the whole list.
class DownloadsBar extends StatelessWidget {
  const DownloadsBar({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([App.downloads, App.downloads.ticks]),
        builder: (context, _) => _bar(),
      );

  Widget _bar() {
    final d = App.downloads;
    final now = d.current;
    if (now == null && d.waiting.isEmpty) return const SizedBox.shrink();
    final more = d.waiting.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Material(
        color: Look.raised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: DownloadsPage.open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(
                  value: now != null && d.size > 0 ? d.progress.clamp(0.0, 1.0) : null,
                  strokeWidth: 3,
                  color: Look.accent,
                  backgroundColor: Look.bg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(now == null ? 'Getting ready' : 'Saving ${now.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(14.5, weight: FontWeight.w700)),
                  Text(more == 0 ? 'The last one' : '$more more waiting',
                      maxLines: 1, style: Look.ui(12.5, color: Look.muted)),
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
