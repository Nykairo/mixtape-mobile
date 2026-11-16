/// Listening together: along with a friend (what they play plays here, at the same second), in a room
/// (one queue for everybody in it) or at a party (the host plays, the guests ask for songs). They are the
/// same rooms as on the computer, so a phone and a computer can sit in one.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mixtape_native/mixtape_native.dart';

import '../account.dart';
import '../app.dart';
import '../look.dart';
import '../model.dart';
import '../rooms.dart' as rooms;
import '../together.dart';
import 'profile_page.dart';
import 'shell.dart';
import 'sign_in.dart';
import 'widgets.dart';

/// The name to show for a profile row: what they call themselves, or their user name.
String _nameOf(Object? profile) {
  if (profile is! Map) return '';
  final shown = '${profile['display_name'] ?? ''}';
  return shown.isNotEmpty ? shown : '${profile['username'] ?? ''}';
}

class TogetherPage extends StatefulWidget {
  const TogetherPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const TogetherPage()));

  @override
  State<TogetherPage> createState() => _TogetherPageState();
}

class _TogetherPageState extends State<TogetherPage> {
  final _friend = TextEditingController();
  final _code = TextEditingController();
  final _guest = TextEditingController();
  final _lookup = TextEditingController();

  void _look() {
    final name = Account.cleanName(_lookup.text);
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    ProfilePage.open(name, over: context);
  }

  /// A person at the party or in the room: their profile, and for the host what they may do there.
  Future<void> _person(Together t, Map<String, Object?> m) async {
    final prof = m['profile'] is Map ? Map<String, Object?>.from(m['profile'] as Map) : <String, Object?>{};
    final uid = '${m['member']}';
    final me = uid == App.account.session?.uid;
    final role = '${m['role'] ?? 'guest'}';
    final pick = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Avatar(prof, size: 40),
            title: Text(_nameOf(prof), style: Look.ui(16, weight: FontWeight.w700)),
            subtitle: Text(switch (role) { 'host' => 'The host', 'dj' => 'A DJ', _ => 'A guest' }, style: Look.ui(13, color: Look.muted)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.person_rounded),
            title: Text(me ? 'Your profile' : 'Their profile'),
            onTap: () => Navigator.of(sheet).pop('profile'),
          ),
          if (t.party && t.isHost && !me && role != 'host') ...[
            ListTile(
              leading: Icon(role == 'dj' ? Icons.person_outline_rounded : Icons.headphones_rounded),
              title: Text(role == 'dj' ? 'Make them a guest again' : 'Make them a DJ'),
              subtitle: Text(role == 'dj' ? 'They ask for songs like everybody' : 'They play the music too',
                  style: Look.ui(13, color: Look.muted)),
              onTap: () => Navigator.of(sheet).pop(role == 'dj' ? 'guest' : 'dj'),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Show them out'),
              onTap: () => Navigator.of(sheet).pop('out'),
            ),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick == 'profile') {
      final name = '${prof['username'] ?? ''}';
      if (name.isNotEmpty) ProfilePage.open(name, over: context);
      return;
    }
    try {
      await t.setRole(uid, pick);
    } on AccountError catch (e) {
      if (mounted) say(context, e.message);
    }
  }

  /// The button that's working right now: 'along', 'room', 'party', 'join' or 'invite'.
  String _busy = '';
  List<Map<String, Object?>> _invites = const [];
  Map<String, Map<String, Object?>> _senders = const {};

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  @override
  void dispose() {
    _friend.dispose();
    _code.dispose();
    _guest.dispose();
    _lookup.dispose();
    super.dispose();
  }

  Future<void> _loadInvites() async {
    if (!App.account.signedIn) return;
    try {
      final rows = await App.account.invites();
      final who = await App.account.people([for (final r in rows) '${r['sender']}']);
      if (!mounted) return;
      setState(() {
        _invites = rows;
        _senders = who;
      });
    } on AccountError {
      // then there are none to show; the page works without them
    }
  }

  /// One of the page's actions, with its button busy meanwhile and what went wrong said in words.
  Future<void> _do(String what, Future<void> Function() action) async {
    if (_busy.isNotEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = what);
    try {
      await action();
    } on AccountError catch (e) {
      if (mounted) say(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _along() => _do('along', () async {
        final name = _friend.text.trim();
        if (name.isEmpty) return;
        await App.together.listenAlong(name);
        _friend.clear();
      });

  Future<void> _open(bool party) => _do(party ? 'party' : 'room', () async {
        await App.together.openRoom(party: party);
      });

  Future<void> _join([String? code]) => _do('join', () async {
        final typed = code ?? _code.text;
        if (typed.trim().isEmpty) return;
        await App.together.joinRoom(typed);
        _code.clear();
        unawaited(_loadInvites());
      });

  Future<void> _invite() => _do('invite', () async {
        final name = _guest.text.trim();
        if (name.isEmpty) return;
        await App.together.invite(name);
        _guest.clear();
      });

  Future<void> _turnDown(String sender) async {
    setState(() => _invites = [
          for (final i in _invites)
            if (i['sender'] != sender) i,
        ]);
    try {
      await App.account.dropInvite(sender);
    } on AccountError {
      // it's gone from the page; the server lets go of old invites by itself
    }
  }

  Future<void> _shareCode(String code, bool party) async {
    final text = 'Join my ${party ? 'party' : 'room'} on Mixtape with the code $code';
    if (Platform.isAndroid && await MixtapeNative.share(text)) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) say(context, 'Code copied');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.together,
      builder: (context, _) {
        final t = App.together;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Look.bg,
            surfaceTintColor: Colors.transparent,
            title: Text('Together', style: Look.ui(19, weight: FontWeight.w800)),
          ),
          body: SafeArea(
            top: false,
            child: Stack(children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  if (!App.account.signedIn)
                    ..._signedOut()
                  else if (t.room != null)
                    ..._room(t)
                  else ...[
                    if (t.friend.isNotEmpty) _Along(t),
                    ..._doors(t),
                  ],
                ],
              ),
              // a party's reactions float up the right side
              if (t.room != null && t.party) Positioned.fill(child: _Floaters(t.reactions.stream)),
            ]),
          ),
        );
      },
    );
  }

  List<Widget> _signedOut() => [
        const SizedBox(height: 12),
        const FractionallySizedBox(widthFactor: 0.62, child: TapeArtPlain(title: 'together', slot: 2, sticky: 'you + me')),
        const SizedBox(height: 22),
        Text('Music is better shared', textAlign: TextAlign.center, style: Look.ui(24, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Listen along with a friend, open a room with one queue for everybody, or throw a party. '
          'All it takes is a Mixtape Account, and it works between phones and computers.',
          textAlign: TextAlign.center,
          style: Look.ui(14.5, color: Look.muted, height: 1.4),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () async {
            await SignInPage.open(context);
            if (!mounted) return;
            setState(() {});
            unawaited(_loadInvites());
          },
          child: const Text('Sign in'),
        ),
      ];

  /// Nothing going on yet: the ways in.
  List<Widget> _doors(Together t) => [
        if (t.friend.isEmpty) ...[
          const SizedBox(height: 6),
          const FractionallySizedBox(widthFactor: 0.5, child: TapeArtPlain(title: 'together', slot: 2, sticky: 'you + me')),
          const SizedBox(height: 6),
        ],
        if (_invites.isNotEmpty) ...[
          const _Heading('Waiting for you'),
          for (final i in _invites)
            _InviteRow(
              from: _nameOf(_senders['${i['sender']}']),
              room: '${i['room_name'] ?? ''}',
              party: i['kind'] == 'party',
              busy: _busy == 'join',
              onJoin: () => _join('${i['code']}'),
              onDrop: () => _turnDown('${i['sender']}'),
            ),
        ],
        _Door(
          icon: Icons.headphones_rounded,
          title: 'Listen along',
          words: 'What a friend plays, here, at the same second. All you need is their user name.',
          child: Row(children: [
            Expanded(
              child: _Field(controller: _friend, hint: 'user name', icon: Icons.alternate_email_rounded, onGo: _along),
            ),
            const SizedBox(width: 10),
            _Go('Listen', busy: _busy == 'along', onTap: _along),
          ]),
        ),
        _Door(
          icon: Icons.groups_rounded,
          title: 'A room',
          words: 'One queue for everybody in it. Anyone can add songs, skip and pause. It starts with what plays here.',
          child: _Go('Open a room', wide: true, busy: _busy == 'room', onTap: () => _open(false)),
        ),
        _Door(
          icon: Icons.celebration_rounded,
          title: 'A party',
          words: 'You play. Your guests ask for songs, and you decide which ones make it.',
          child: _Go('Throw a party', wide: true, busy: _busy == 'party', onTap: () => _open(true)),
        ),
        _Door(
          icon: Icons.person_search_rounded,
          title: 'Look someone up',
          words: 'Their picture, their song, the tape they have on show and what they play most.',
          child: Row(children: [
            Expanded(
              child: _Field(controller: _lookup, hint: 'user name', icon: Icons.alternate_email_rounded, onGo: _look),
            ),
            const SizedBox(width: 10),
            _Go('Look', busy: false, onTap: _look),
          ]),
        ),
        _Door(
          icon: Icons.vpn_key_rounded,
          title: 'Got a code?',
          words: 'Six letters and digits from whoever opened the room.',
          child: Row(children: [
            Expanded(child: _Field(controller: _code, hint: 'ABC234', caps: true, max: 7, onGo: _join)),
            const SizedBox(width: 10),
            _Go('Join', busy: _busy == 'join', onTap: _join),
          ]),
        ),
      ];

  /// In a room or at a party: its code, who's there, what was asked for, and the queue.
  List<Widget> _room(Together t) {
    final names = {
      for (final m in t.members)
        if (m['profile'] case final Map<Object?, Object?> p) '${p['username'] ?? ''}': _nameOf(p),
    };
    final byId = {for (final m in t.members) '${m['member']}': _nameOf(m['profile'])};
    final present = {for (final p in t.here.values) '${p['user'] ?? ''}'};
    final now = rooms.currentOf(t.state);
    final next = rooms.upcoming(t.state);
    final last = rooms.said(t.state, t.me, names);
    final paused = t.state['paused'] == true;
    return [
      _Ticket(
        party: t.party,
        name: '${t.room?['name'] ?? ''}',
        code: t.code,
        host: t.isHost,
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: t.code));
          if (mounted) say(context, 'Code copied');
        },
        onShare: () => _shareCode(t.code, t.party),
      ),
      if (last.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Text(last, textAlign: TextAlign.center, style: Look.ui(13, color: Look.muted)),
        ),
      if (t.party) ...[
        const SizedBox(height: 14),
        _Reactions(onSend: t.react),
      ],
      const _Heading('Here'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (t.members.isEmpty)
          for (final p in t.here.values) _Person(name: '${p['name'] ?? p['user'] ?? ''}', here: true)
        else
          for (final m in t.members)
            _Person(
              name: _nameOf(m['profile']),
              host: m['role'] == 'host',
              dj: m['role'] == 'dj',
              here: present.contains('${(m['profile'] as Map?)?['username'] ?? ''}'),
              onTap: () => _person(t, m),
            ),
      ]),
      if (t.party && t.isHost) ...[
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: t.takesRequests,
          activeThumbColor: Look.accent,
          title: Text('Take requests', style: Look.ui(15.5)),
          subtitle: Text('Guests can ask for songs.', style: Look.ui(13, color: Look.muted)),
          onChanged: (v) => t.setTakeRequests(v).catchError((Object e) {
            if (mounted && e is AccountError) say(context, e.message);
          }),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: t.open,
          activeThumbColor: Look.accent,
          title: Text('Let new people in', style: Look.ui(15.5)),
          subtitle: Text('Off: nobody new comes in with the code.', style: Look.ui(13, color: Look.muted)),
          onChanged: (v) => t.setOpen(v).catchError((Object e) {
            if (mounted && e is AccountError) say(context, e.message);
          }),
        ),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: _Field(
              controller: _guest, hint: 'invite a friend by user name', icon: Icons.person_add_alt_1_rounded, onGo: _invite),
        ),
        const SizedBox(width: 10),
        _Go('Invite', busy: _busy == 'invite', onTap: _invite),
      ]),
      if (t.party && t.canSteer && t.requests.isNotEmpty) ...[
        const _Heading('Asked for'),
        for (final r in t.requests)
          _RequestRow(
            request: r,
            from: byId['${r['member']}'] ?? '',
            onTake: () => t.answer(r, true),
            onLeave: () => t.answer(r, false),
          ),
      ],
      _Heading(now == null ? 'The queue' : (paused ? 'Paused' : 'Playing')),
      if (now != null)
        _QueueRow(item: now, by: names['${now['by']}'] ?? '${now['by']}', current: true, paused: paused),
      if (next.isNotEmpty) ...[
        const _Heading('Up next'),
        for (final it in next)
          _QueueRow(
            item: it,
            by: names['${it['by']}'] ?? '${it['by']}',
            onTap: t.canSteer ? () => t.playKey('${it['k']}') : null,
            onRemove: t.canSteer ? () => t.removeKey('${it['k']}') : null,
          ),
      ],
      if (now == null && next.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            t.canSteer
                ? 'Nothing in the queue yet. Find a song, open its menu and add it to the room.'
                : 'Nothing in the queue yet. Find a song, open its menu and ask the host for it.',
            style: Look.ui(14, color: Look.muted, height: 1.4),
          ),
        ),
      const SizedBox(height: 16),
      FilledButton.tonalIcon(
        onPressed: () {
          Navigator.of(context).pop();
          Shell.goTo(2);
        },
        icon: const Icon(Icons.search_rounded),
        label: Text(t.canSteer ? 'Find songs for the queue' : 'Find a song to ask for'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: t.leaveRoom,
        icon: const Icon(Icons.logout_rounded),
        label: Text(t.party ? (t.isHost ? 'End the party' : 'Leave the party') : 'Leave the room'),
      ),
    ];
  }
}

// ---------------------------------------------------------------- the pieces

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Text(text.toUpperCase(), style: Look.cond(13, spacing: 2.2)),
      );
}

/// One of the ways in: what it is in a sentence, and its button or field.
class _Door extends StatelessWidget {
  const _Door({required this.icon, required this.title, required this.words, required this.child});

  final IconData icon;
  final String title;
  final String words;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Look.side,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Look.edge),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: Look.accent.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Icon(icon, color: Look.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: Look.ui(17, weight: FontWeight.w800))),
        ]),
        const SizedBox(height: 10),
        Text(words, style: Look.ui(13.5, color: Look.muted, height: 1.4)),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, required this.onGo, this.icon, this.caps = false, this.max = 24});

  final TextEditingController controller;
  final String hint;
  final VoidCallback onGo;
  final IconData? icon;
  final bool caps;
  final int max;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: max,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
      textInputAction: TextInputAction.go,
      onSubmitted: (_) => onGo(),
      style: caps ? Look.cond(20, color: Look.cream, spacing: 4) : Look.ui(16),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        isDense: true,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
      ),
    );
  }
}

class _Go extends StatelessWidget {
  const _Go(this.text, {required this.onTap, this.busy = false, this.wide = false});

  final String text;
  final VoidCallback onTap;
  final bool busy;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: busy ? null : onTap,
      child: busy
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Look.bg))
          : Text(text),
    );
    return wide ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Listening along with a friend: who, what they play, and the way out.
class _Along extends StatelessWidget {
  const _Along(this.t);

  final Together t;

  @override
  Widget build(BuildContext context) {
    final now = t.friendNow;
    final title = '${now?['title'] ?? ''}';
    final artist = '${now?['artist'] ?? ''}';
    final song = title.isEmpty
        ? null
        : Track(src: 'yt', ref: '${now?['id'] ?? ''}', title: title, artist: artist);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Look.accent, Look.stripes[1]],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LISTENING ALONG WITH', style: Look.cond(12.5, color: Look.bg, spacing: 2.2)),
        const SizedBox(height: 2),
        Text(t.friendName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(26, weight: FontWeight.w900, color: Look.bg)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Look.bg.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            if (song != null) Cover(song, size: 46) else const Icon(Icons.pause_circle_outline_rounded, size: 34, color: Look.muted),
            const SizedBox(width: 12),
            Expanded(
              child: song == null
                  ? Text('Nothing playing right now. It starts here as soon as it starts there.',
                      style: Look.ui(13.5, color: Look.muted, height: 1.35))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15.5, weight: FontWeight.w700)),
                      Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13, color: Look.muted)),
                    ]),
            ),
            if (song != null) PlayingBars(playing: now?['playing'] == true),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text('Pause, skip or pick a song and the music is yours again.',
                style: Look.ui(12.5, weight: FontWeight.w600, color: Look.bg, height: 1.3)),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Look.bg, foregroundColor: Look.cream),
            onPressed: () => t.stopAlong(why: 'The music is yours again'),
            child: const Text('Stop'),
          ),
        ]),
      ]),
    );
  }
}

/// The room's ticket: what it is, its name, and the code to pass on, a letter per box.
class _Ticket extends StatelessWidget {
  const _Ticket({
    required this.party,
    required this.name,
    required this.code,
    required this.host,
    required this.onCopy,
    required this.onShare,
  });

  final bool party;
  final String name;
  final String code;
  final bool host;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Look.accent, Look.stripes[1]],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: [
        Text('${party ? 'PARTY' : 'ROOM'}${host ? '  ·  YOU HOST' : ''}', style: Look.cond(12.5, color: Look.bg, spacing: 2.4)),
        if (name.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Look.ui(20, weight: FontWeight.w900, color: Look.bg, height: 1.15)),
        ],
        const SizedBox(height: 14),
        GestureDetector(
          onTap: onCopy,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final ch in code.split(''))
              Container(
                width: 40,
                height: 50,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Look.bg, borderRadius: BorderRadius.circular(8)),
                child: Text(ch, style: Look.cond(28, color: Look.cream, spacing: 0)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Look.bg),
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy the code'),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Look.bg),
            onPressed: onShare,
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Send it'),
          ),
        ]),
      ]),
    );
  }
}

/// Somebody in the room: their first letter in a circle, their name, a crown on the host. Members
/// who aren't there right now are greyed.
class _Person extends StatelessWidget {
  const _Person({required this.name, this.host = false, this.dj = false, this.here = false, this.onTap});

  final String name;
  final bool host;
  final bool dj;
  final bool here;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shown = name.isEmpty ? 'someone' : name;
    return Opacity(
      opacity: here ? 1 : 0.5,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(
          color: Look.raised,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: host ? Look.accent : Look.edge),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: here ? Look.accent : Look.faint,
            child: Text(shown.characters.first.toUpperCase(), style: Look.ui(13, weight: FontWeight.w800, color: Look.bg)),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(13.5, weight: FontWeight.w600)),
          ),
          if (host) ...[
            const SizedBox(width: 5),
            Icon(Icons.star_rounded, size: 15, color: Look.accent),
          ],
          if (dj) ...[
            const SizedBox(width: 5),
            Icon(Icons.headphones_rounded, size: 15, color: Look.accent),
          ],
        ]),
        ),
      ),
    );
  }
}

/// What guests send up at a party: five little icons, for everybody there.
class _Reactions extends StatelessWidget {
  const _Reactions({required this.onSend});

  final void Function(String kind) onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: Look.raised, borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (final kind in Together.reactionKinds)
          IconButton(
            tooltip: kind,
            onPressed: () => onSend(kind),
            icon: Icon(reactionIcon(kind), color: reactionColor(kind)),
          ),
      ]),
    );
  }
}

IconData reactionIcon(String kind) => switch (kind) {
      'heart' => Icons.favorite_rounded,
      'flame' => Icons.local_fire_department_rounded,
      'sparkle' => Icons.auto_awesome_rounded,
      'star' => Icons.star_rounded,
      _ => Icons.music_note_rounded,
    };

Color reactionColor(String kind) => switch (kind) {
      'heart' => const Color(0xFFFF5F8F),
      'flame' => const Color(0xFFFF6A1A),
      'sparkle' => const Color(0xFFFFD567),
      'star' => const Color(0xFFE7B24A),
      _ => const Color(0xFF4DA3FF),
    };

/// Reactions floating up and fading out along the right side, a couple of seconds each. Nothing
/// runs while none are in the air.
class _Floaters extends StatefulWidget {
  const _Floaters(this.reactions);

  final Stream<String> reactions;

  @override
  State<_Floaters> createState() => _FloatersState();
}

class _FloatersState extends State<_Floaters> with TickerProviderStateMixin {
  final _flying = <(String, double, AnimationController)>[];
  StreamSubscription<String>? _heard;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _heard = widget.reactions.listen(_launch);
  }

  void _launch(String kind) {
    if (!mounted || _flying.length >= 24) return;
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: 2200 + _random.nextInt(800)));
    final entry = (kind, _random.nextDouble(), c);
    setState(() => _flying.add(entry));
    c.forward().whenComplete(() {
      c.dispose();
      if (mounted) setState(() => _flying.remove(entry));
    });
  }

  @override
  void dispose() {
    _heard?.cancel();
    for (final (_, _, c) in _flying) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => Stack(children: [
          for (final (kind, lane, c) in _flying)
            AnimatedBuilder(
              animation: c,
              builder: (context, child) {
                final t = c.value;
                return Positioned(
                  right: 18 + lane * 60 + sin(t * pi * 3 + lane * 6) * 10,
                  bottom: 40 + t * box.maxHeight * 0.55,
                  child: Opacity(opacity: (1 - t).clamp(0.0, 1.0), child: Transform.scale(scale: 0.8 + t * 0.5, child: child)),
                );
              },
              child: Icon(reactionIcon(kind), color: reactionColor(kind), size: 30),
            ),
        ]),
      ),
    );
  }
}

/// A song in the room's queue: the one that plays with the dancing bars, the ones to come with a way
/// to take them off (for whoever steers).
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.item,
    required this.by,
    this.current = false,
    this.paused = false,
    this.onTap,
    this.onRemove,
  });

  final rooms.RoomItem item;
  final String by;
  final bool current;
  final bool paused;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Track.fromJson(item['t']);
    if (t == null) return const SizedBox.shrink();
    final under = [if (t.artist.isNotEmpty) t.artist, if (by.isNotEmpty) 'from $by'].join('  ·  ');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Cover(t, size: current ? 54 : 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Look.ui(current ? 16.5 : 15, weight: FontWeight.w700, color: current ? Look.accent : Look.cream)),
              const SizedBox(height: 2),
              Text(under, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(12.5, color: Look.muted)),
            ]),
          ),
          if (current) PlayingBars(playing: !paused),
          if (onRemove != null)
            IconButton(
              tooltip: 'Take it out of the queue',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 20, color: Look.muted),
            ),
        ]),
      ),
    );
  }
}

/// A song a guest asked the host of a party for.
class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request, required this.from, required this.onTake, required this.onLeave});

  final Map<String, Object?> request;
  final String from;
  final VoidCallback onTake;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final t = Track.fromJson(request['song']);
    if (t == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Cover(t, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15, weight: FontWeight.w700)),
            Text([if (t.artist.isNotEmpty) t.artist, if (from.isNotEmpty) '$from asks'].join('  ·  '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(12.5, color: Look.muted)),
          ]),
        ),
        IconButton(
          tooltip: 'Not this one',
          onPressed: onLeave,
          icon: const Icon(Icons.close_rounded, color: Look.muted),
        ),
        IconButton.filled(
          tooltip: 'Into the queue',
          onPressed: onTake,
          icon: const Icon(Icons.add_rounded),
        ),
      ]),
    );
  }
}

/// An invite to a room that's waiting: who, where to, and yes or no.
class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.from,
    required this.room,
    required this.party,
    required this.busy,
    required this.onJoin,
    required this.onDrop,
  });

  final String from;
  final String room;
  final bool party;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final who = from.isEmpty ? 'Somebody' : from;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: Look.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Look.accent.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(party ? Icons.celebration_rounded : Icons.groups_rounded, color: Look.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$who invites you', maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(15, weight: FontWeight.w700)),
            Text(room.isEmpty ? (party ? 'to a party' : 'to a room') : room,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(12.5, color: Look.muted)),
          ]),
        ),
        IconButton(
          tooltip: 'Not now',
          onPressed: onDrop,
          icon: const Icon(Icons.close_rounded, color: Look.muted),
        ),
        FilledButton(onPressed: busy ? null : onJoin, child: const Text('Join')),
        const SizedBox(width: 6),
      ]),
    );
  }
}
