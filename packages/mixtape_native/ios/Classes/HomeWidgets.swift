// The widgets draw again when what they show changed (kept apart from the rest: WidgetKit and the
// photo picker don't get along in one file with Xcode 26).

import WidgetKit

enum HomeWidgets {
  static func redraw() {
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
  }
}
