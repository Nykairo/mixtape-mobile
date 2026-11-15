/// Settings: the tape stock, music that keeps going, whether friends can listen along, the songs saved
/// on the phone, the account, and what Mixtape is made of.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import '../phone.dart';
import 'pages.dart';
import 'shell.dart';
import 'sign_in.dart';
import 'widgets.dart';

const appVersion = '0.2.0';

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
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final e in Look.stocks.entries)
                    _Stock(name: e.key, colors: e.value, on: e.key == Look.stock),
                ],
              ),
            ),
            const SectionTitle('Playing'),
            SwitchListTile(
              value: App.settings.autoplay,
              activeThumbColor: Look.accent,
              title: Text('Keep the music going', style: Look.ui(15.5)),
              subtitle: Text('When a list ends, songs like the last one play on.', style: Look.ui(13, color: Look.muted)),
              onChanged: (on) {
                App.settings.setAutoplay(on);
                App.audio.autoplay = on;
              },
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
                subtitle: Text('@${s.username}', style: Look.ui(13, color: Look.muted)),
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
          width: 84,
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
            Text(name, style: Look.ui(13, weight: on ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
