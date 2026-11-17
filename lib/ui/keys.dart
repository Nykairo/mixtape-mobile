/// The computer's keys, for a phone or tablet with a keyboard (Samsung DeX, a keyboard cover, a
/// Chromebook), the same as on the computer: Space plays or pauses, Ctrl+Left and Ctrl+Right jump ten
/// seconds, Ctrl+F searches, Ctrl+P opens the player, Ctrl+N makes a new tape, Alt+Left goes back,
/// Ctrl+E and Ctrl+I save the library to a file and take one in, Ctrl+Shift+L is Listen together,
/// Ctrl+Shift+I imports a playlist and Ctrl+, opens Settings. While a text field has the keys, they
/// type into it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import 'add_music.dart';
import 'now_playing.dart';
import 'search.dart';
import 'settings_page.dart';
import 'shell.dart';
import 'tape_page.dart';
import 'together_page.dart';
import 'widgets.dart';

class Keys extends StatelessWidget {
  const Keys({super.key, required this.child});

  final Widget child;

  static final _keys = <SingleActivator, void Function(BuildContext)>{
    const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false): (_) =>
        App.audio.player.playing ? App.audio.pause() : App.audio.play(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): (_) => _jump(-10),
    const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): (_) => _jump(10),
    const SingleActivator(LogicalKeyboardKey.keyF, control: true, includeRepeats: false): (_) {
      Shell.goTo(2);
      SearchPage.typeIn();
    },
    const SingleActivator(LogicalKeyboardKey.keyP, control: true, includeRepeats: false): (c) {
      if (App.audio.current != null) NowPlaying.open(c);
    },
    const SingleActivator(LogicalKeyboardKey.keyN, control: true, includeRepeats: false): _newTape,
    const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true, includeRepeats: false): (c) =>
        Navigator.of(c, rootNavigator: true).maybePop(),
    const SingleActivator(LogicalKeyboardKey.keyE, control: true, includeRepeats: false): saveLibrary,
    const SingleActivator(LogicalKeyboardKey.keyI, control: true, includeRepeats: false): takeInLibrary,
    const SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true, includeRepeats: false): TogetherPage.open,
    const SingleActivator(LogicalKeyboardKey.keyI, control: true, shift: true, includeRepeats: false): (_) =>
        Shell.push(const ImportPage()),
    const SingleActivator(LogicalKeyboardKey.comma, control: true, includeRepeats: false): (_) =>
        Shell.push(const SettingsPage()),
  };

  static void _jump(int seconds) {
    final player = App.audio.player;
    final to = player.position + Duration(seconds: seconds);
    final end = player.duration;
    if (end == null) return;
    App.audio.seek(to < Duration.zero ? Duration.zero : (to > end ? end : to));
  }

  static Future<void> _newTape(BuildContext context) async {
    final name = await askText(context, title: 'New tape', hint: 'Name it', action: 'Make it');
    if (name == null) return;
    Shell.push(TapePage(tape: App.library.newTape(name)));
  }

  /// A text field has the keys: Space is a space there, Ctrl+Left a word back.
  static bool _typing() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null;

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _typing()) return KeyEventResult.ignored;
    final context = Shell.stateKey.currentContext;
    if (context == null) return KeyEventResult.ignored;
    for (final MapEntry(:key, :value) in _keys.entries) {
      if (key.accepts(event, HardwareKeyboard.instance)) {
        value(context);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // the whole app's keys go through here; Tab skips it, and the screen reader never hears of it
  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, skipTraversal: true, includeSemantics: false, onKeyEvent: _key, child: child);
}
