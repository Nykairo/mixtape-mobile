// The keys on the widgets (iOS 17 and newer). This file is in the app too: an audio intent the app
// has runs inside the app, which hands the key to the player through the plugin
// (MixtapeNativePlugin.swift, widgetKey).

import AppIntents
import Foundation

@available(iOS 17.0, *)
struct WidgetKey: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Mixtape key"

  /// play, pause, next, previous, like, shuffle, or tape: and a tape's id
  @Parameter(title: "Key")
  var what: String

  init() {}

  init(_ what: String) {
    self.what = what
  }

  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: Notification.Name("MixtapeWidgetKey"), object: nil, userInfo: ["what": what])
    return .result()
  }
}
