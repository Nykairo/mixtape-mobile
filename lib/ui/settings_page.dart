/// Settings: the tape stock, music that keeps going, the account, and what Mixtape is made of.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../look.dart';
import 'sign_in.dart';
import 'widgets.dart';

const appVersion = '0.1.0';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([App.settings, App.library]),
      builder: (context, _) {
        final s = App.account.session;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Look.bg,
            surfaceTintColor: Colors.transparent,
            title: Text('Settings', style: Look.ui(19, weight: FontWeight.w700)),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 28), children: [
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
              title: Text('Mixtape $appVersion for Android', style: Look.ui(15.5)),
              subtitle: Text(
                'Open source (GPL 3). Songs come from YouTube Music through NewPipe Extractor. Made by MinieChaos.',
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
