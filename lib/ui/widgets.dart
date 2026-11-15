/// The small pieces the pages are built from: covers, song rows and the song menu, cards and rows for
/// albums, artists and playlists, tape tiles, pills, the download button, the tape counter and the bars
/// that dance next to the song that plays.
library;

import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mixtape_native/mixtape_native.dart';

import '../app.dart';
import '../cassette.dart';
import '../look.dart';
import '../model.dart';
import '../music.dart';
import 'pages.dart';
import 'shell.dart';

/// Tells the person something, at the bottom of the screen.
void say(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/// A song's link to send to someone: the phone's share sheet on Android, copied on the iPhone.
Future<void> shareSong(BuildContext context, Track t) async {
  final link = t.src == 'yt' ? 'https://music.youtube.com/watch?v=${t.ref}' : t.ref;
  final text = '${t.title}${t.artist.isEmpty ? '' : ' by ${t.artist}'}\n$link';
  if (Platform.isAndroid && await MixtapeNative.share(text)) return;
  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) say(context, 'Link copied');
}

/// A picture from the internet, decoded at the size it shows (so a list of a hundred stays light).
class Pic extends StatelessWidget {
  const Pic(this.url, {super.key, this.size = 48, this.radius = 6, this.round = false, this.file, this.icon});

  final String url;
  final double size;
  final double radius;
  final bool round;
  final File? file;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final Widget blank = ColoredBox(
      color: Look.raised,
      child: Center(child: Icon(icon ?? Icons.album_outlined, color: Look.faint, size: size * 0.42)),
    );
    final f = file;
    final Widget image = f != null
        ? Image.file(f, width: size, height: size, fit: BoxFit.cover, cacheWidth: px, errorBuilder: (_, __, ___) => blank)
        : url.isEmpty
            ? blank
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: px,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => blank,
                frameBuilder: (_, child, frame, sync) => frame == null && !sync ? blank : child,
              );
    return SizedBox.square(
      dimension: size,
      child: round ? ClipOval(child: image) : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image),
    );
  }
}

/// A song's cover (the saved one when the song is on the phone).
class Cover extends StatelessWidget {
  const Cover(this.track, {super.key, this.size = 48, this.radius = 6});

  final Track track;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final px = size * MediaQuery.devicePixelRatioOf(context);
    return Pic(track.artAt(px <= 120 ? 120 : (px <= 300 ? 300 : 544)),
        size: size, radius: radius, file: App.downloads.coverOf(track));
  }
}

/// A heading over a part of a page: a small line over a big one, the way YouTube Music does it, and
/// maybe a "More" button.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.over = '', this.trailing, this.onMore});

  final String text;
  final String over;
  final Widget? trailing;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 12, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (over.isNotEmpty) Text(over.toUpperCase(), style: Look.cond(12, spacing: 2)),
            Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(21, weight: FontWeight.w800)),
          ]),
        ),
        if (trailing != null) trailing!,
        if (onMore != null)
          OutlinedButton(
            onPressed: onMore,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              minimumSize: const Size(0, 32),
              shape: const StadiumBorder(),
              textStyle: Look.ui(13, weight: FontWeight.w700),
            ),
            child: const Text('More'),
          ),
      ]),
    );
  }
}

/// Builds with the id of the song that plays and whether it plays.
class NowPlayingBuilder extends StatelessWidget {
  const NowPlayingBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, MediaItem? item, bool playing) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: App.audio.mediaItem,
      initialData: App.audio.mediaItem.valueOrNull,
      builder: (context, item) => StreamBuilder<bool>(
        stream: App.audio.playbackState.map((s) => s.playing).distinct(),
        initialData: App.audio.playbackState.valueOrNull?.playing ?? false,
        builder: (context, playing) => builder(context, item.data, playing.data ?? false),
      ),
    );
  }
}

/// A rounded button with an icon and a word, the chips under YouTube Music's player.
class Pill extends StatelessWidget {
  const Pill(this.icon, this.text, this.onTap, {super.key, this.on = false, this.color});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool on;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = on ? Look.cream : (color ?? Colors.white.withValues(alpha: 0.08));
    final fg = on ? Look.bg : Look.cream;
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(text, style: Look.ui(13.5, weight: FontWeight.w700, color: fg)),
          ]),
        ),
      ),
    );
  }
}

/// One song in a list: cover (or its place on a tape), title, artist and length, whether it's on the
/// phone, and the menu. The song that plays shows it.
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.track,
    required this.onTap,
    this.current = false,
    this.playing = false,
    this.tape,
    this.index,
    this.number,
  });

  final Track track;
  final VoidCallback onTap;
  final bool current;
  final bool playing;
  final Tape? tape; // the tape the row is on, for "Take off this tape"
  final int? index;
  final int? number; // a place number instead of the cover (on tapes and albums, like a tracklist)

  @override
  Widget build(BuildContext context) {
    final can = track.playable;
    final saved = App.downloads.has(track);
    final title = Text(
      track.title.isEmpty ? 'Untitled' : track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Look.ui(15.5, weight: FontWeight.w600, color: current ? Look.accent : (can ? Look.cream : Look.faint)),
    );
    final sub = [
      if (track.artist.isNotEmpty) track.artist,
      if (track.dur > 0) clock(track.dur),
      if (!can) track.src == 'local' ? 'on the computer' : "doesn't play here",
    ].join('  ·  ');
    return InkWell(
      onTap: can ? onTap : () => say(context, "That song is a file on a computer, it doesn't play on the phone."),
      onLongPress: () => songMenu(context, track, tape: tape, index: index),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 4, 7),
        child: Row(children: [
          if (number != null)
            SizedBox(
              width: 30,
              child: current
                  ? PlayingBars(playing: playing, size: 16)
                  : Text('${number!}', textAlign: TextAlign.center, style: Look.cond(15, color: Look.faint)),
            )
          else
            Stack(alignment: Alignment.center, children: [
              Cover(track, size: 48),
              if (current)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Center(child: PlayingBars(playing: playing, size: 18)),
                ),
            ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              title,
              if (sub.isNotEmpty || saved)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    if (saved) ...[
                      Icon(Icons.arrow_circle_down_rounded, size: 14, color: Look.accent),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
                    ),
                  ]),
                ),
            ]),
          ),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, color: Look.faint),
            onPressed: () => songMenu(context, track, tape: tape, index: index),
          ),
        ]),
      ),
    );
  }
}

/// Everything that can be done with a song: up top the four things done most, then the rest.
Future<void> songMenu(BuildContext context, Track t, {Tape? tape, int? index}) {
  final lib = App.library;
  final together = App.together;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) {
      void done(String? word) {
        Navigator.of(sheet).pop();
        if (word != null) say(context, word);
      }

      final liked = lib.isLiked(t);
      final saved = App.downloads.has(t);
      final artistId = '${t.extra['artist_id'] ?? ''}';
      final albumId = '${t.extra['album_id'] ?? ''}';
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: Cover(t, size: 46),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5, weight: FontWeight.w700)),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
                trailing: IconButton(
                  tooltip: liked ? 'Unlike' : 'Like',
                  onPressed: () {
                    final now = lib.toggleLike(t);
                    done(now ? 'In your liked songs' : 'Out of your liked songs');
                  },
                  icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: liked ? Look.accent : Look.muted),
                ),
              ),
              if (t.playable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Row(children: [
                    _Big(Icons.playlist_play_rounded, 'Play next', () {
                      App.audio.playNext(t);
                      done('Plays after this one');
                    }),
                    _Big(Icons.queue_music_rounded, 'Add to queue', () {
                      App.audio.addSongs([t]);
                      done('Added to the queue');
                    }),
                    _Big(Icons.library_add_rounded, 'Put on tape', () async {
                      Navigator.of(sheet).pop();
                      await pickTape(context, [t]);
                    }),
                    _Big(Icons.ios_share_rounded, 'Share', () {
                      Navigator.of(sheet).pop();
                      shareSong(context, t);
                    }),
                  ]),
                ),
              const Divider(height: 1),
              if (t.src == 'yt')
                _MenuRow(Icons.radio_rounded, 'Start radio', () {
                  App.audio.playSongs([t], from: '${t.title} radio');
                  done('Playing ${t.title}, and songs like it after');
                }),
              if (artistId.isNotEmpty || t.artist.isNotEmpty)
                _MenuRow(Icons.person_outline_rounded, 'Go to ${t.artist.split(',').first}', () {
                  Navigator.of(sheet).pop();
                  Shell.push(artistId.isNotEmpty
                      ? ArtistView(id: artistId, name: t.artist.split(',').first)
                      : SearchResultsView(query: t.artist.split(',').first, filter: 'artists'));
                }),
              if (albumId.isNotEmpty)
                _MenuRow(Icons.album_outlined, 'Go to the album', () {
                  Navigator.of(sheet).pop();
                  Shell.push(AlbumView(id: albumId, title: t.album));
                }),
              if (t.src == 'yt')
                _MenuRow(saved ? Icons.delete_outline_rounded : Icons.arrow_circle_down_rounded,
                    saved ? 'Take off the phone' : 'Save on the phone', () {
                  if (saved) {
                    App.downloads.remove([t]);
                    done('Taken off the phone');
                  } else {
                    App.downloads.save([t]);
                    done('Saving ${t.title} on the phone');
                  }
                }),
              if (together.room != null && t.playable)
                _MenuRow(Icons.groups_rounded, together.canSteer ? 'Add to the room' : 'Ask the host for it', () {
                  together.addSongs([t]);
                  done(together.canSteer ? 'In the room' : null);
                }),
              if (t.src == 'yt')
                _MenuRow(lib.isHidden(t) ? Icons.visibility_rounded : Icons.do_not_disturb_on_outlined,
                    lib.isHidden(t) ? 'Interested again' : 'Not interested', () {
                  final now = !lib.isHidden(t);
                  lib.hide(t, now);
                  done(now
                      ? "Got it. It won't come up in your mixes, radios and Samples anymore."
                      : 'It can come up in your mixes again');
                }),
              if (tape != null && index != null)
                _MenuRow(Icons.remove_circle_outline_rounded, 'Take off this tape', () {
                  lib.removeAt(tape, index);
                  done('Off ${tape.shownName}');
                }),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      );
    },
  );
}

class _Big extends StatelessWidget {
  const _Big(this.icon, this.text, this.onTap);

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: Look.raised,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(children: [
                  Icon(icon, color: Look.cream),
                  const SizedBox(height: 6),
                  Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(12, weight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text, this.onTap);

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: Look.muted),
        title: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5)),
        onTap: onTap,
        dense: true,
        visualDensity: const VisualDensity(vertical: 0.5),
      );
}

/// Which tape the songs go on (or a new one).
Future<void> pickTape(BuildContext context, List<Track> songs) async {
  final lib = App.library;
  final tapes = [
    for (final t in lib.shownTapes.reversed)
      if (t.group == null) t,
  ];
  final picked = await showModalBottomSheet<Object>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('PUT ON A TAPE', style: Look.cond(13.5, spacing: 2.2)),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded, color: Look.cream),
            title: Text('New tape', style: Look.ui(15.5, weight: FontWeight.w600)),
            onTap: () => Navigator.of(sheet).pop(true),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: tapes.length,
              itemBuilder: (_, k) {
                final tape = tapes[k];
                return ListTile(
                  leading: SizedBox(width: 56, child: TapeArt(tape: tape, small: true)),
                  title: Text(tape.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5)),
                  subtitle: Text(count(tape.songs.length), style: Look.ui(13, color: Look.muted)),
                  onTap: () => Navigator.of(sheet).pop(tape),
                );
              },
            ),
          ),
        ]),
      ),
    ),
  );
  if (!context.mounted || picked == null) return;
  Tape? tape = picked is Tape ? picked : null;
  if (picked == true) {
    final name = await askText(context, title: 'New tape', hint: 'Name it', action: 'Make it');
    if (name == null || !context.mounted) return;
    tape = lib.newTape(name);
  }
  if (tape == null) return;
  final n = lib.addTo(tape, songs);
  say(context, n == 0 ? 'Already on ${tape.shownName}' : 'On ${tape.shownName}');
}

String count(int n, [String what = 'song']) => n == 1 ? '1 $what' : '$n ${what}s';

/// Asks for a line of text (a tape's name, say). Null when the person changed their mind.
Future<String?> askText(BuildContext context,
    {required String title, String hint = '', String start = '', String action = 'OK', int max = 80, bool blank = false}) {
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _Ask(title: title, hint: hint, start: start, action: action, max: max, blank: blank),
  );
}

class _Ask extends StatefulWidget {
  const _Ask({
    required this.title,
    required this.hint,
    required this.start,
    required this.action,
    required this.max,
    required this.blank,
  });

  final String title, hint, start, action;
  final int max;

  /// Whether nothing is an answer too (a sticky note can be taken off by leaving it empty).
  final bool blank;

  @override
  State<_Ask> createState() => _AskState();
}

class _AskState extends State<_Ask> {
  late final _field = TextEditingController(text: widget.start);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _done() {
    final v = _field.text.trim();
    Navigator.of(context).pop(v.isEmpty && !widget.blank ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Look.side,
      title: Text(widget.title, style: Look.ui(19, weight: FontWeight.w700)),
      content: TextField(
        controller: _field,
        autofocus: true,
        maxLength: widget.max,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint, counterText: ''),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _done, child: Text(widget.action)),
      ],
    );
  }
}

/// A tape as a little cassette with its own label, paper and decorations.
class TapeArt extends StatelessWidget {
  const TapeArt({super.key, required this.tape, this.small = false, this.playing = false});

  final Tape tape;
  final bool small;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Cassette(
      title: small ? '' : tape.shownName,
      slot: tape.paper ?? slotFor(tape.name),
      design: tape.design,
      layer: App.library.layerOf(tape),
      sticky: small ? '' : tape.note,
      leftNote: small ? '' : tapeFor(tape.seconds),
      rightNote: small ? '' : count(tape.songs.length),
      playing: playing,
    );
  }
}

/// The liked songs as a tape of their own (the computer writes "don't tape over!" on its note).
class LikedArt extends StatelessWidget {
  const LikedArt({super.key, this.small = false, this.playing = false});

  final bool small;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final liked = App.library.liked;
    return Cassette(
      title: small ? '' : 'Liked songs',
      slot: 3,
      sticky: small ? '' : "don't tape over!",
      leftNote: small ? '' : tapeFor(liked.fold(0, (s, t) => s + t.dur)),
      rightNote: small ? '' : count(liked.length),
      playing: playing,
    );
  }
}

/// A cassette with nothing but a title on its label (the cream paper of the tape stock).
class TapeArtPlain extends StatelessWidget {
  const TapeArtPlain({super.key, required this.title, this.playing = false, this.sticky = '', this.slot = 0, this.design});

  final String title;
  final bool playing;
  final String sticky;
  final int slot;
  final Map<String, Object?>? design;

  @override
  Widget build(BuildContext context) =>
      Cassette(title: title, slot: slot, sticky: sticky, playing: playing, design: design);
}

/// A tape in a grid or a row: the cassette and its name under it.
class TapeTile extends StatelessWidget {
  const TapeTile({super.key, required this.tape, required this.onTap, this.width = 168});

  final Tape tape;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TapeArt(tape: tape),
            const SizedBox(height: 8),
            Text(tape.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(14.5, weight: FontWeight.w600)),
            Text('${count(tape.songs.length)}  ·  ${tapeFor(tape.seconds)}',
                maxLines: 1, style: Look.ui(12.5, color: Look.muted)),
          ]),
        ),
      ),
    );
  }
}

/// An album, a playlist, an artist or a video as a card in a row: the picture (round for an artist),
/// its name and the line under it.
class ItemCard extends StatelessWidget {
  const ItemCard(this.item, {super.key, this.width = 150, this.list});

  final Item item;
  final double width;

  /// For a song or video: the list it plays in.
  final List<Item>? list;

  @override
  Widget build(BuildContext context) {
    final round = item.kind == Kind.artist;
    final wide = item.kind == Kind.video;
    final h = (width - 10) * 9 / 16;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () => openItem(context, item, list: list),
        onLongPress: item.playable ? () => songMenu(context, item.track) : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Column(crossAxisAlignment: round ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
            if (wide)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: width - 10, height: h, child: _WidePic(item.art)),
              )
            else
              Pic(item.art, size: width - 10, radius: 8, round: round, icon: round ? Icons.person_rounded : null),
            const SizedBox(height: 8),
            Text(item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: round ? TextAlign.center : TextAlign.start,
                style: Look.ui(14, weight: FontWeight.w600, height: 1.2)),
            if (item.subtitle.isNotEmpty)
              Text(item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: round ? TextAlign.center : TextAlign.start,
                  style: Look.ui(12.5, color: Look.muted)),
          ]),
        ),
      ),
    );
  }
}

class _WidePic extends StatelessWidget {
  const _WidePic(this.url);

  final String url;

  @override
  Widget build(BuildContext context) => url.isEmpty
      ? const ColoredBox(color: Look.raised)
      : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Look.raised));
}

/// A row of cards that scrolls sideways.
class CardRow extends StatelessWidget {
  const CardRow(this.items, {super.key, this.width = 150});

  final List<Item> items;
  final double width;

  @override
  Widget build(BuildContext context) {
    // videos get wider cards; the row is as high as its tallest card: the picture, the gap, two lines
    // of title and one under it (in the size the phone sets the letters to), and the padding round it
    final video = items.isNotEmpty && items.every((i) => i.kind == Kind.video);
    final card = video ? width * 1.35 : width;
    final picture = items.any((i) => i.kind != Kind.video) ? card - 10 : (card - 10) * 9 / 16;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: picture + 18 + 52 * scale,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        itemBuilder: (_, k) => ItemCard(items[k], width: card, list: items),
      ),
    );
  }
}

/// A search result of any kind, as a row.
class ItemRow extends StatelessWidget {
  const ItemRow(this.item, {super.key, this.list});

  final Item item;
  final List<Item>? list;

  @override
  Widget build(BuildContext context) {
    if (item.playable) {
      final songs = [
        for (final i in list ?? [item])
          if (i.playable) i.track,
      ];
      final t = item.track;
      return NowPlayingBuilder(
        builder: (context, now, playing) => SongRow(
          track: t,
          current: now?.id == t.id,
          playing: playing,
          onTap: () => App.audio.playSongs(songs, start: max(0, songs.indexWhere((x) => x.id == t.id)), from: 'Search'),
        ),
      );
    }
    final kind = switch (item.kind) {
      Kind.album => 'Album',
      Kind.artist => 'Artist',
      Kind.playlist => 'Playlist',
      _ => '',
    };
    final sub = [kind, if (item.subtitle.isNotEmpty) item.subtitle].join('  ·  ');
    return InkWell(
      onTap: () => openItem(context, item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
        child: Row(children: [
          Pic(item.art, size: 48, radius: 6, round: item.kind == Kind.artist, icon: item.kind == Kind.artist ? Icons.person_rounded : null),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5, weight: FontWeight.w600)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: Look.faint),
        ]),
      ),
    );
  }
}

/// Opens what was tapped: a song or a video plays (in its list), the rest opens its page.
void openItem(BuildContext context, Item item, {List<Item>? list}) {
  switch (item.kind) {
    case Kind.song || Kind.video:
      final songs = [
        for (final i in list ?? [item])
          if (i.playable) i.track,
      ];
      final start = max(0, songs.indexWhere((t) => t.ref == item.id));
      App.audio.playSongs(songs, start: start, from: item.kind == Kind.video ? 'Videos' : 'Songs');
    case Kind.artist:
      App.library.openedItem({'kind': 'artist', 'id': item.id, 'title': item.title, 'art': item.art});
      Shell.push(ArtistView(id: item.id, name: item.title));
    case Kind.album || Kind.playlist:
      App.library.openedItem({
        'kind': item.kind == Kind.album ? 'album' : 'playlist',
        'id': item.id,
        'title': item.title,
        'art': item.art,
        'subtitle': item.subtitle,
      });
      Shell.push(AlbumView(id: item.id, title: item.title));
    case Kind.other:
      say(context, "That doesn't open here");
  }
}

/// Saves a list of songs on the phone, shows how far it is, or takes them off again.
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.songs, this.name = '', this.size = 40});

  final List<Track> songs;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.downloads,
      builder: (context, _) {
        final d = App.downloads;
        final (have, total) = d.count(songs);
        final busy = d.busyWith(songs);
        final all = total > 0 && have == total;
        return IconButton(
          tooltip: busy ? 'Saving on the phone. Tap to stop' : (all ? 'On the phone' : 'Save on the phone'),
          iconSize: size * 0.62,
          onPressed: total == 0
              ? null
              : () async {
                  if (busy) {
                    d.cancel(songs);
                    say(context, 'Stopped. What came down stays on the phone.');
                  } else if (all) {
                    final sure = await _askRemove(context, name);
                    if (sure == true) await d.remove(songs);
                  } else {
                    final n = d.save(songs, name: name.isEmpty ? 'Your songs' : name);
                    if (context.mounted && n > 0) say(context, 'Saving ${count(n)} on the phone');
                  }
                },
          icon: SizedBox.square(
            dimension: size * 0.7,
            child: Stack(alignment: Alignment.center, children: [
              if (busy)
                CircularProgressIndicator(
                  strokeWidth: 2.4,
                  value: total == 0 ? null : (have + d.progress) / total,
                  color: Look.accent,
                  backgroundColor: Look.edge,
                ),
              Icon(
                all ? Icons.arrow_circle_down_rounded : (busy ? Icons.stop_rounded : Icons.arrow_circle_down_outlined),
                size: busy ? size * 0.38 : size * 0.62,
                color: all ? Look.accent : Look.cream,
              ),
            ]),
          ),
        );
      },
    );
  }

  static Future<bool?> _askRemove(BuildContext context, String name) => showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (d) => AlertDialog(
          backgroundColor: Look.side,
          title: Text('Take ${name.isEmpty ? 'these songs' : name} off the phone?', style: Look.ui(19, weight: FontWeight.w700)),
          content: Text('They stay where they are, they just need the internet again.',
              style: Look.ui(15, color: Look.muted, height: 1.4)),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Keep them')),
            FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Take them off')),
          ],
        ),
      );
}

/// Little bars that dance next to the song that plays (and stand still while it's paused).
class PlayingBars extends StatefulWidget {
  const PlayingBars({super.key, required this.playing, this.size = 18, this.color});

  final bool playing;
  final double size;
  final Color? color;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _a.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_a.isAnimating) {
      _a.repeat();
    } else if (!widget.playing && _a.isAnimating) {
      _a.stop();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _BarsPainter(_a, widget.color ?? Look.accent)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.a, this.color) : super(repaint: a);

  final Animation<double> a;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 4.6;
    final p = Paint()..color = color;
    for (var k = 0; k < 3; k++) {
      final t = a.value * 2 * pi + k * 2.1;
      final h = size.height * (0.3 + 0.7 * (0.5 + 0.5 * sin(t * (k == 1 ? 2 : 1) + k)).abs());
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(k * w * 1.8, size.height - h, w, h), Radius.circular(w / 2)), p);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color;
}

/// The tape counter: digits in lit segments, the way the deck on the computer shows the time.
class Counter extends StatelessWidget {
  const Counter(this.text, {super.key, this.height = 22, this.color});

  final String text;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(_Segments.widthOf(text, height), height),
      painter: _Segments(text, color ?? Look.accent),
    );
  }
}

class _Segments extends CustomPainter {
  _Segments(this.text, this.on);

  final String text;
  final Color on;

  static double _w(String ch, double h) => ch == ':' ? h * 0.32 : h * 0.62;

  static double widthOf(String text, double h) => text.split('').fold(0.0, (s, ch) => s + _w(ch, h));

  // which of the seven segments each digit lights: top, top right, bottom right, bottom, bottom left,
  // top left, middle
  static const _digits = {
    '0': [1, 1, 1, 1, 1, 1, 0],
    '1': [0, 1, 1, 0, 0, 0, 0],
    '2': [1, 1, 0, 1, 1, 0, 1],
    '3': [1, 1, 1, 1, 0, 0, 1],
    '4': [0, 1, 1, 0, 0, 1, 1],
    '5': [1, 0, 1, 1, 0, 1, 1],
    '6': [1, 0, 1, 1, 1, 1, 1],
    '7': [1, 1, 1, 0, 0, 0, 0],
    '8': [1, 1, 1, 1, 1, 1, 1],
    '9': [1, 1, 1, 1, 0, 1, 1],
    '-': [0, 0, 0, 0, 0, 0, 1],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final lit = Paint()..color = on;
    final ghost = Paint()..color = on.withValues(alpha: 0.1);
    final glow = Paint()
      ..color = on.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    var x = 0.0;
    for (final ch in text.split('')) {
      final cw = _w(ch, h);
      if (ch == ':') {
        final r = h * 0.055;
        for (final y in [h * 0.32, h * 0.7]) {
          canvas.drawCircle(Offset(x + cw / 2, y), r, glow);
          canvas.drawCircle(Offset(x + cw / 2, y), r, lit);
        }
      } else {
        final segs = _digits[ch] ?? const [0, 0, 0, 0, 0, 0, 0];
        final t = h * 0.1; // stroke
        final dw = cw - h * 0.14, left = x + h * 0.07;
        final rects = [
          Rect.fromLTWH(left + t * 0.6, 0, dw - t * 1.2, t),
          Rect.fromLTWH(left + dw - t, t * 0.6, t, h / 2 - t * 0.9),
          Rect.fromLTWH(left + dw - t, h / 2 + t * 0.3, t, h / 2 - t * 0.9),
          Rect.fromLTWH(left + t * 0.6, h - t, dw - t * 1.2, t),
          Rect.fromLTWH(left, h / 2 + t * 0.3, t, h / 2 - t * 0.9),
          Rect.fromLTWH(left, t * 0.6, t, h / 2 - t * 0.9),
          Rect.fromLTWH(left + t * 0.6, h / 2 - t / 2, dw - t * 1.2, t),
        ];
        for (var k = 0; k < 7; k++) {
          final rr = RRect.fromRectAndRadius(rects[k], Radius.circular(t / 2));
          if (segs[k] == 1) {
            canvas.drawRRect(rr, glow);
            canvas.drawRRect(rr, lit);
          } else {
            canvas.drawRRect(rr, ghost);
          }
        }
      }
      x += cw;
    }
  }

  @override
  bool shouldRepaint(_Segments old) => old.text != text || old.on != on;
}
