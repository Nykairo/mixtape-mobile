/// What every page works with: the music, the library, the account and the settings. They are made
/// once when the app starts (see main.dart) and live as long as the app.
library;

import 'account.dart';
import 'audio.dart';
import 'library.dart';
import 'settings.dart';

class App {
  static late MixtapeAudio audio;
  static late Library library;
  static late Account account;
  static late Settings settings;
}
