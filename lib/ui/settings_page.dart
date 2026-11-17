/// Settings: the tape stock, music that keeps going, whether friends can listen along, the songs saved
/// on the phone, the account, and what Mixtape is made of.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mixtape_native/mixtape_native.dart';

import '../app.dart';
import '../blend.dart';
import '../look.dart';
import '../phone.dart';
import '../scrobble.dart';
import 'pages.dart';
import 'profile_page.dart';
import 'shell.dart';
import 'sign_in.dart';
import 'widgets.dart';

/// The library into a file, handed to the share sheet (to the files, a chat, or the computer).
Future<void> _saveLibrary(BuildContext context) async {
  try {
    final f = await App.library.exportFile();
    final shared = await MixtapeNative.shareFile(f.path, mime: 'application/json', text: 'My Mixtape library');
    if (!shared && context.mounted) say(context, 'This phone has no way to send the file on');
  } on FileSystemException {
    if (context.mounted) say(context, "The phone is full: the library didn't fit in a file");
  }
}

/// A library file from the phone's files, taken in next to what's here.
Future<void> _takeInLibrary(BuildContext context) async {
  final path = await MixtapeNative.pickFile();
  if (path == null || !context.mounted) return;
  say(context, 'Taking it in…');
  try {
    final (likes, tapes) = await App.library.importFile(path);
    if (!context.mounted) return;
    say(context, likes == 0 && tapes == 0
        ? 'Everything in it is here already'
        : 'In: ${count(likes, 'liked song')} and ${count(tapes, 'tape')}');
  } on FormatException {
    if (context.mounted) say(context, "That isn't a Mixtape library");
  } on FileSystemException {
    if (context.mounted) say(context, "That file couldn't be read");
  } finally {
    File(path).delete().ignore(); // the picker's copy of it
  }
}

/// ListenBrainz on (a token, checked first) or off.
Future<void> _listenBrainz(BuildContext context) async {
  final settings = App.settings;
  if (settings.listenBrainzToken.isNotEmpty) {
    settings.setListenBrainz('', '');
    say(context, 'ListenBrainz is off. What you listen to stays here.');
    return;
  }
  final token = await askText(context, title: 'Your ListenBrainz token', hint: 'from listenbrainz.org/settings', action: 'Connect', max: 80);
  if (token == null || token.trim().isEmpty || !context.mounted) return;
  try {
    final user = await Scrobbler.check(token);
    settings.setListenBrainz(token, user);
    if (context.mounted) say(context, 'Scrobbling to ListenBrainz as $user');
  } on ScrobbleTrouble catch (e) {
    if (context.mounted) say(context, e.why);
  }
}

/// 3.4 MB, 1.2 GB: how much room the saved songs take.
String sizeWords(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
  return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _clearSaved(BuildContext context) async {
    final songs = [for (final s in App.downloads.all) s.track];
    final sure = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (d) => AlertDialog(
        backgroundColor: Look.side,
        title: Text('Take all ${songs.length} songs off the phone?', style: Look.ui(19, weight: FontWeight.w700)),
        content: Text('Your tapes stay as they are. The songs just need the internet again.',
            style: Look.ui(15, color: Look.muted, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Keep them')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Take them off')),
        ],
      ),
    );
    if (sure != true) return;
    await App.downloads.remove(songs);
    if (context.mounted) say(context, 'The phone has its room back');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([App.settings, App.library, App.downloads]),
      builder: (context, _) {
        final s = App.account.session;
        final saved = App.downloads.all.length;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Look.bg,
            surfaceTintColor: Colors.transparent,
            title: Text('Settings', style: Look.ui(19, weight: FontWeight.w700)),
          ),
          body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 28), children: [
            const SectionTitle('Tape stock'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('The color of what plays, and of the stripes on plain labels.',
                  style: Look.ui(13.5, color: Look.muted)),
            ),
            const SizedBox(height: 12),
            // all of them side by side, however narrow the phone
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                for (final e in Look.stocks.entries)
                  Expanded(child: _Stock(name: e.key, colors: e.value, on: e.key == Look.stock)),
              ]),
            ),
            const SectionTitle('Playing'),
            SwitchListTile(
              value: App.settings.autoplay,
              activeThumbColor: Look.accent,
              title: Text('Radio', style: Look.ui(15.5)),
              subtitle: Text('When the queue ends, songs like the last ones keep coming.', style: Look.ui(13, color: Look.muted)),
              onChanged: (on) {
                App.settings.setAutoplay(on);
                App.audio.autoplay = on;
              },
            ),
            const SectionTitle('Between songs'),
            const _Crossfade(),
            const SectionTitle('Lyrics'),
            SwitchListTile(
              value: App.settings.lyricsCountdown,
              activeThumbColor: Look.accent,
              title: Text('Count down to every line', style: Look.ui(15.5)),
              subtitle: Text('A little clock next to lyrics that follow the song closes its ring as the next line comes.',
                  style: Look.ui(13, color: Look.muted, height: 1.35)),
              onChanged: App.settings.setLyricsCountdown,
            ),
            SwitchListTile(
              value: App.settings.rewindNote,
              activeThumbColor: Look.accent,
              title: Text('Tell me when my Rewind is ready', style: Look.ui(15.5)),
              subtitle: Text("Early in the month, Home says when last month's Rewind is there to play.",
                  style: Look.ui(13, color: Look.muted, height: 1.35)),
              onChanged: App.settings.setRewindNote,
            ),
            if (Platform.isAndroid) ...[
              const SectionTitle('With the screen off'),
              ListenableBuilder(listenable: PhoneInfo.the, builder: (context, _) => const _Background()),
            ],
            const SectionTitle('Together'),
            SwitchListTile(
              value: App.settings.shareListening,
              activeThumbColor: Look.accent,
              title: Text('Friends can listen along', style: Look.ui(15.5)),
              subtitle: Text(
                s == null
                    ? 'With a Mixtape Account, a friend who knows your user name hears what plays here. '
                        'Mixtape on your computer then shows it on your Discord too.'
                    : 'A friend who types @${s.username} hears what plays here, at the same second. '
                        'Mixtape on your computer shows it on your Discord too.',
                style: Look.ui(13, color: Look.muted, height: 1.35),
              ),
              onChanged: (on) {
                App.settings.setShareListening(on);
                App.together.sharingChanged();
              },
            ),
            const SectionTitle('Saved on this phone'),
            ListTile(
              leading: const Icon(Icons.download_done_rounded, color: Look.muted),
              title: Text(saved == 0 ? 'Nothing saved yet' : '$saved ${saved == 1 ? 'song' : 'songs'}, ${sizeWords(App.downloads.bytes)}',
                  style: Look.ui(15.5)),
              subtitle: Text(
                saved == 0
                    ? 'The arrow on a tape, an album or a song saves it for when there is no internet.'
                    : 'They play without the internet. Tap to see them.',
                style: Look.ui(13, color: Look.muted, height: 1.35),
              ),
              onTap: saved == 0
                  ? null
                  : () => Shell.push(MixView(
                        title: 'On this phone',
                        blurb: 'no internet needed',
                        songs: [for (final x in App.downloads.all) x.track],
                        slot: 3,
                      )),
            ),
            if (saved > 0)
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined, color: Look.muted),
                title: Text('Take them all off the phone', style: Look.ui(15.5)),
                onTap: () => _clearSaved(context),
              ),
            const SectionTitle('Your library in a file'),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: Look.muted),
              title: Text('Save it to a file', style: Look.ui(15.5)),
              subtitle: Text(
                'Liked songs and tapes with their notes and decorations, for another phone or the computer '
                '(Ctrl+I there).',
                style: Look.ui(13, color: Look.muted, height: 1.35),
              ),
              onTap: () => _saveLibrary(context),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined, color: Look.muted),
              title: Text('Take one in', style: Look.ui(15.5)),
              subtitle: Text(
                "A library file from the computer (Ctrl+E there) or another phone. What's here stays as it is.",
                style: Look.ui(13, color: Look.muted, height: 1.35),
              ),
              onTap: () => _takeInLibrary(context),
            ),
            const SectionTitle('ListenBrainz and Last.fm'),
            ListTile(
              leading: const Icon(Icons.graphic_eq_rounded, color: Look.muted),
              title: Text(App.settings.listenBrainzUser.isEmpty ? 'Send what I listen to ListenBrainz' : 'Scrobbling to ListenBrainz',
                  style: Look.ui(15.5)),
              subtitle: Text(
                  App.settings.listenBrainzUser.isEmpty
                      ? 'Your token from listenbrainz.org/settings. Friends there see what plays here and can listen along.'
                      : 'As ${App.settings.listenBrainzUser}. Tap to stop.',
                  style: Look.ui(13, color: Look.muted, height: 1.35)),
              onTap: () => _listenBrainz(context),
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined, color: Look.muted),
              title: Text('Last.fm API key', style: Look.ui(15.5)),
              subtitle: Text(
                  App.settings.lastFmKey.isEmpty
                      ? 'For listening along with people on Last.fm. A free one comes from last.fm/api.'
                      : 'Set. Tap to change it.',
                  style: Look.ui(13, color: Look.muted, height: 1.35)),
              onTap: () async {
                final key = await askText(context,
                    title: 'Last.fm API key', hint: '32 letters and digits', start: App.settings.lastFmKey, action: 'Keep', max: 64, blank: true);
                if (key != null) App.settings.setLastFmKey(key);
              },
            ),
            const SectionTitle('Mixtape Account'),
            if (s == null)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded, color: Look.muted),
                title: Text('Sign in', style: Look.ui(15.5)),
                subtitle: Text('Your tapes and liked songs from the computer', style: Look.ui(13, color: Look.muted)),
                onTap: () => SignInPage.open(context),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.person_rounded, color: Look.muted),
                title: Text(s.display, style: Look.ui(15.5)),
                subtitle: Text('@${s.username}  ·  your profile', style: Look.ui(13, color: Look.muted)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Look.muted),
                onTap: () => ProfilePage.open(s.username),
              ),
              ListTile(
                leading: const Icon(Icons.sync_rounded, color: Look.muted),
                title: Text('Bring the tapes in step now', style: Look.ui(15.5)),
                subtitle: Text(App.library.trouble ?? 'They also do by themselves', style: Look.ui(13, color: Look.muted)),
                trailing: App.library.syncing
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
                onTap: App.library.syncing ? null : App.library.sync,
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Look.muted),
                title: Text('Sign out', style: Look.ui(15.5)),
                subtitle: Text('Your tapes stay on this phone', style: Look.ui(13, color: Look.muted)),
                onTap: () async {
                  await App.together.leaveRoom();
                  App.together.stopAlong();
                  await App.together.stopSharing();
                  await App.library.sync();
                  await App.account.signOut();
                  App.library.signedOut();
                  if (context.mounted) say(context, 'Signed out');
                },
              ),
            ],
            const SectionTitle('About'),
            ListTile(
              leading: const Icon(Icons.album_rounded, color: Look.muted),
              title: Text('Mixtape $appVersion for ${Platform.isIOS ? 'iPhone' : 'Android'}', style: Look.ui(15.5)),
              subtitle: Text(
                'Open source (GPL 3). Songs come from YouTube Music, lyrics from lrclib and YouTube Music. '
                'Made by MinieChaos.',
                style: Look.ui(13, color: Look.muted, height: 1.35),
              ),
              onTap: () => showLicensePage(context: context, applicationName: 'Mixtape', applicationVersion: appVersion),
            ),
          ]),
        );
      },
    );
  }
}

/// Music with the screen off: whether Android's battery saving leaves Mixtape alone, and on phones whose
/// maker adds a battery manager of its own, where to let Mixtape off there too.
/// Crossfade: on or off, how long the two songs overlap (a drawing of the two volumes shows it), the
/// shape of the blend, and whether an album's songs run into each other as they were made.
class _Crossfade extends StatelessWidget {
  const _Crossfade();

  @override
  Widget build(BuildContext context) {
    final set = App.settings;
    final on = set.crossfade > 0;
    final secs = on ? set.crossfade : set.crossfadeWas;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        value: on,
        activeThumbColor: Look.accent,
        title: Text('Crossfade', style: Look.ui(15.5)),
        subtitle: Text('The song that ends blends into the next one, the way a DJ does. A skip still cuts.',
            style: Look.ui(13, color: Look.muted, height: 1.35)),
        onChanged: (v) => set.setCrossfade(seconds: v ? set.crossfadeWas : 0),
      ),
      if (on) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
          child: SizedBox(
            height: 74,
            child: CustomPaint(size: Size.infinite, painter: FadePicture(set.fadeShape, secs / longestFade)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 18, 0),
          child: Row(children: [
            Expanded(
              child: Slider(
                value: secs,
                min: 1,
                max: longestFade,
                divisions: ((longestFade - 1) * 2).round(),
                activeColor: Look.accent,
                label: '${_secs(secs)} s',
                onChanged: (v) => set.setCrossfade(seconds: v),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text('${_secs(secs)} s', textAlign: TextAlign.end, style: Look.ui(15, weight: FontWeight.w700)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in fadeShapes.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: set.fadeShape == e.key,
                showCheckmark: false,
                labelStyle: Look.ui(13.5, weight: FontWeight.w600, color: set.fadeShape == e.key ? Look.bg : Look.cream),
                selectedColor: Look.cream,
                backgroundColor: Look.raised,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                onSelected: (_) => set.setCrossfade(shape: e.key),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
          child: Text(fadeShapeAbout[set.fadeShape] ?? '', style: Look.ui(13, color: Look.muted, height: 1.35)),
        ),
        SwitchListTile(
          value: set.albumsWhole,
          activeThumbColor: Look.accent,
          title: Text('Albums play straight through', style: Look.ui(15.5)),
          subtitle: Text('Two songs that follow each other on one album run into each other the way they were made.',
              style: Look.ui(13, color: Look.muted, height: 1.35)),
          onChanged: (v) => set.setCrossfade(albums: v),
        ),
      ],
    ]);
  }

  static String _secs(double s) => s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);
}

/// The two volumes of a crossfade over time: the song that ends going down, the next one coming up,
/// the blend as wide as [part] of the longest one.
class FadePicture extends CustomPainter {
  const FadePicture(this.shape, this.part);

  final String shape;
  final double part;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final floor = h - 6;
    const top = 8.0;
    final blend = w * (0.18 + 0.64 * part.clamp(0.0, 1.0));
    final x0 = (w - blend) / 2;
    final grid = Paint()
      ..color = Look.edge
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, floor), Offset(w, floor), grid);
    Path line(bool ending) {
      final path = Path()..moveTo(0, ending ? top : floor);
      path.lineTo(x0, ending ? top : floor);
      for (var k = 0; k <= 48; k++) {
        final f = k / 48;
        final (out, into) = blendGains(shape, f);
        path.lineTo(x0 + blend * f, floor - (floor - top) * (ending ? out : into));
      }
      path.lineTo(w, ending ? floor : top);
      return path;
    }

    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line(true), pen..color = Look.cream.withValues(alpha: 0.55));
    canvas.drawPath(line(false), pen..color = Look.accent);
    final shade = Paint()..color = Look.accent.withValues(alpha: 0.08);
    canvas.drawRect(Rect.fromLTRB(x0, top - 4, x0 + blend, floor), shade);
  }

  @override
  bool shouldRepaint(FadePicture old) => old.shape != shape || old.part != part;
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    final p = PhoneInfo.the;
    return Column(children: [
      if (p.batteryFree)
        ListTile(
          leading: const Icon(Icons.battery_full_rounded, color: Look.muted),
          title: Text('Battery saving leaves Mixtape alone', style: Look.ui(15.5)),
          subtitle: Text('The music keeps going with the screen off.', style: Look.ui(13, color: Look.muted)),
        )
      else
        ListTile(
          leading: Icon(Icons.battery_alert_rounded, color: Look.accent),
          title: Text('Let the music play with the screen off', style: Look.ui(15.5)),
          subtitle: Text("Android's battery saving can stop it after a while. One tap asks it not to.",
              style: Look.ui(13, color: Look.muted, height: 1.35)),
          onTap: p.askBatteryFree,
        ),
      if (p.isStrict)
        ListTile(
          leading: const Icon(Icons.tune_rounded, color: Look.muted),
          title: Text('${p.name} settings', style: Look.ui(15.5)),
          subtitle: Text(p.tip, style: Look.ui(13, color: Look.muted, height: 1.35)),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: Look.muted),
          onTap: p.openMakerSettings,
        ),
    ]);
  }
}

class _Stock extends StatelessWidget {
  const _Stock({required this.name, required this.colors, required this.on});

  final String name;
  final List<Color> colors;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => App.settings.setStock(name),
        child: Container(
          height: 72,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Look.side,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? colors[0] : Look.edge, width: on ? 2 : 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              for (final c in colors) Expanded(child: Container(height: 10, color: c)),
            ]),
            const SizedBox(height: 8),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Look.ui(13, weight: on ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
