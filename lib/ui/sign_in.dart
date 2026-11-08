/// Signing in to the Mixtape Account (the same one as on the computer), or making one.
library;

import 'package:flutter/material.dart';

import '../account.dart';
import '../app.dart';
import '../look.dart';
import 'widgets.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const SignInPage()));

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _shown = TextEditingController();
  bool _new = false; // making an account instead of signing in
  bool _busy = false;
  bool _see = false;
  String? _trouble;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _shown.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _trouble = null;
    });
    try {
      final s = _new
          ? await App.account.signUp(_name.text, _password.text, display: _shown.text)
          : await App.account.signIn(_name.text, _password.text);
      App.library.signedIn();
      if (!mounted) return;
      Navigator.of(context).pop();
      say(context, _new ? 'Welcome, ${s.display}. Your Mixtape Account is ready.' : 'Signed in as @${s.username}');
    } on AccountError catch (e) {
      if (mounted) setState(() => _trouble = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Look.bg, surfaceTintColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          const FractionallySizedBox(widthFactor: 0.7, child: TapeArtPlain(title: 'Mixtape Account', slot: 4, sticky: 'hi!')),
          const SizedBox(height: 24),
          Text(_new ? 'Make your Mixtape Account' : 'Sign in to Mixtape',
              textAlign: TextAlign.center, style: Look.ui(24, weight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            _new
                ? 'A user name and a password is all it takes. Your tapes and liked songs then go everywhere you sign in.'
                : 'The same user name and password as in Mixtape on your computer.',
            textAlign: TextAlign.center,
            style: Look.ui(14.5, color: Look.muted, height: 1.4),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            style: Look.ui(16),
            decoration: const InputDecoration(hintText: 'User name', prefixIcon: Icon(Icons.alternate_email_rounded)),
          ),
          const SizedBox(height: 12),
          if (_new) ...[
            TextField(
              controller: _shown,
              textInputAction: TextInputAction.next,
              maxLength: 40,
              style: Look.ui(16),
              decoration: const InputDecoration(
                  hintText: 'Your name, as friends see it (you can leave it)',
                  prefixIcon: Icon(Icons.badge_outlined),
                  counterText: ''),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _password,
            obscureText: !_see,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            autofillHints: [_new ? AutofillHints.newPassword : AutofillHints.password],
            onSubmitted: (_) => _go(),
            style: Look.ui(16),
            decoration: InputDecoration(
              hintText: _new ? 'Password (8 characters or more)' : 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _see ? 'Hide it' : 'Show it',
                icon: Icon(_see ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _see = !_see),
              ),
            ),
          ),
          if (_trouble != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_trouble!, style: Look.ui(14, color: Look.accent, height: 1.35)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Look.bg))
                : Text(_new ? 'Make it' : 'Sign in'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _new = !_new;
                      _trouble = null;
                    }),
            child: Text(_new ? 'I have an account already' : 'No account yet? Make one'),
          ),
        ],
      ),
    );
  }
}
