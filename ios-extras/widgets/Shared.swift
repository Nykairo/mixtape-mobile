// What the iPhone widgets show, as the app leaves it in the App Group they share (the plugin's
// MixtapeNativePlugin.swift writes it): the song that plays, and the tapes for "My tapes".

import SwiftUI
import UIKit

enum Shared {
  /// The App Group. Sideloading tools give it a name of their own and say which in ALTAppGroups.
  static let group: String = {
    if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let first = groups.first {
      return first
    }
    return "group.dev.softwarevault.mixtape"
  }()

  static func json(_ key: String) -> Any? {
    guard let text = UserDefaults(suiteName: group)?.string(forKey: key), let data = text.data(using: .utf8) else {
      return nil
    }
    return try? JSONSerialization.jsonObject(with: data)
  }

  static func song() -> Song? {
    guard let j = json("playing") as? [String: Any], let title = j["title"] as? String else { return nil }
    var cover: UIImage?
    if let art = j["art"] as? String, !art.isEmpty,
       let box = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
      cover = UIImage(contentsOfFile: box.appendingPathComponent(art).path)
    }
    let at = (j["at"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
    return Song(
      title: title,
      artist: j["artist"] as? String ?? "",
      playing: j["playing"] as? Bool ?? false,
      liked: j["liked"] as? Bool ?? false,
      shuffle: j["shuffle"] as? Bool ?? false,
      position: ((j["position"] as? NSNumber)?.doubleValue ?? 0) / 1000,
      duration: ((j["duration"] as? NSNumber)?.doubleValue ?? 0) / 1000,
      at: Date(timeIntervalSince1970: at),
      index: (j["index"] as? NSNumber)?.intValue ?? 0,
      count: (j["count"] as? NSNumber)?.intValue ?? 0,
      look: TapeColors(j["colors"] as? [String: Any]),
      cover: cover
    )
  }

  static func shelf() -> [ShelfTape] {
    guard let list = json("shelf") as? [[String: Any]] else { return [] }
    return list.map {
      ShelfTape(
        id: $0["id"] as? String ?? "",
        name: $0["name"] as? String ?? "",
        songs: ($0["songs"] as? NSNumber)?.intValue ?? 0,
        look: TapeColors($0["colors"] as? [String: Any]),
        liked: $0["liked"] as? Bool ?? false
      )
    }
  }
}

/// A color as the app says it: one number, ARGB.
struct ARGB {
  var value: UInt32

  init(_ value: UInt32) {
    self.value = value
  }

  var a: Double { Double((value >> 24) & 0xFF) / 255 }
  var r: Double { Double((value >> 16) & 0xFF) / 255 }
  var g: Double { Double((value >> 8) & 0xFF) / 255 }
  var b: Double { Double(value & 0xFF) / 255 }

  var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

  /// Light enough for dark things on it.
  var light: Bool { 0.299 * r + 0.587 * g + 0.114 * b > 150.0 / 255 }

  func mixed(with other: ARGB, _ t: Double) -> ARGB {
    func ch(_ x: Double, _ y: Double) -> UInt32 { UInt32(max(0, min(255, ((x + (y - x) * t) * 255).rounded()))) }
    return ARGB(ch(a, other.a) << 24 | ch(r, other.r) << 16 | ch(g, other.g) << 8 | ch(b, other.b))
  }

  func withAlpha(_ alpha: Double) -> ARGB {
    ARGB(UInt32(max(0, min(255, (alpha * 255).rounded()))) << 24 | (value & 0x00FF_FFFF))
  }

  static let white = ARGB(0xFFFF_FFFF)
  static let black = ARGB(0xFF00_0000)
}

/// A tape's cassette colors (the app's TapeLook, as numbers).
struct TapeColors {
  var shell = ARGB(0xFF2E_2621)
  var shellAlpha = 1.0
  var paper = ARGB(0xFFF1_E6CF)
  var ink = ARGB(0xFF25_428E)
  var stripes = [ARGB(0xFFFF_6A1A), ARGB(0xFFFF_A323), ARGB(0xFFFF_D567)]
  var stripeStyle = "classic"
  var hub = ARGB(0xFFEC_E4D4)
  var tape = ARGB(0xFF3B_2618)
  var screw = ARGB(0xFFB9_B4AC)
  var screws = true

  /// Mixtape's own cassette: warm black, cream label, the three stripes.
  static let plain = TapeColors()

  init() {}

  init(_ j: [String: Any]?) {
    guard let j = j else { return }
    func number(_ key: String) -> ARGB? {
      (j[key] as? NSNumber).map { ARGB(UInt32(truncatingIfNeeded: $0.int64Value)) }
    }
    shell = number("shell") ?? shell
    shellAlpha = ((j["shellAlpha"] as? NSNumber)?.doubleValue ?? 255) / 255
    paper = number("paper") ?? paper
    ink = number("ink") ?? ink
    if let list = j["stripes"] as? [NSNumber], !list.isEmpty {
      stripes = list.map { ARGB(UInt32(truncatingIfNeeded: $0.int64Value)) }
    }
    stripeStyle = j["stripeStyle"] as? String ?? stripeStyle
    hub = number("hub") ?? hub
    tape = number("tape") ?? tape
    screw = number("screw") ?? screw
    screws = j["screws"] as? Bool ?? screws
  }
}

struct Song {
  var title: String
  var artist: String
  var playing: Bool
  var liked: Bool
  var shuffle: Bool
  var position: Double // seconds into the song when the app said so
  var duration: Double
  var at: Date // when the app said so
  var index: Int
  var count: Int
  var look: TapeColors
  var cover: UIImage?

  /// When the song started, counted back from where it was when the app said so.
  var started: Date { at.addingTimeInterval(-position) }

  /// How far into the tape the music is, 0 to 1: the reels show it.
  var along: Double { count <= 0 ? 0 : min(1, max(0, (Double(index) + 0.5) / Double(count))) }

  static let sample = Song(title: "Midnight City", artist: "M83", playing: true, liked: true, shuffle: false,
                           position: 74, duration: 243, at: Date(), index: 3, count: 12, look: .plain, cover: nil)
}

struct ShelfTape: Identifiable {
  var id: String
  var name: String
  var songs: Int
  var look: TapeColors
  var liked: Bool

  static let samples: [ShelfTape] = {
    var night = TapeColors()
    night.shell = ARGB(0xFF1F_2A44)
    night.paper = ARGB(0xFFE8_EEF6)
    night.stripes = [ARGB(0xFF5B_8CFF), ARGB(0xFF9F_B8FF), ARGB(0xFFD6_E2FF)]
    var summer = TapeColors()
    summer.shell = ARGB(0xFFF2_C14E)
    summer.paper = ARGB(0xFFFF_F8E7)
    summer.stripes = [ARGB(0xFFE8_5D3A), ARGB(0xFFF2_9E4C), ARGB(0xFFF7_D488)]
    var mint = TapeColors()
    mint.shell = ARGB(0xFF7F_C8B2)
    mint.paper = ARGB(0xFFF4_FBF8)
    return [
      ShelfTape(id: "", name: "Liked songs", songs: 42, look: .plain, liked: true),
      ShelfTape(id: "night", name: "Night drive", songs: 18, look: night, liked: false),
      ShelfTape(id: "summer", name: "Summer 26", songs: 25, look: summer, liked: false),
      ShelfTape(id: "focus", name: "Focus", songs: 30, look: mint, liked: false),
    ]
  }()
}

/// Mixtape's own colors for the widgets.
enum Deck {
  static let back = Color(.sRGB, red: 0x19 / 255.0, green: 0x14 / 255.0, blue: 0x10 / 255.0, opacity: 1)
  static let raised = Color(.sRGB, red: 0x2A / 255.0, green: 0x21 / 255.0, blue: 0x1C / 255.0, opacity: 1)
  static let cream = Color(.sRGB, red: 0xF6 / 255.0, green: 0xEC / 255.0, blue: 0xD8 / 255.0, opacity: 1)
  static let muted = Color(.sRGB, red: 0xB4 / 255.0, green: 0xA6 / 255.0, blue: 0x92 / 255.0, opacity: 1)
  static let orange = Color(.sRGB, red: 1, green: 0x6A / 255.0, blue: 0x1A / 255.0, opacity: 1)

  static func hand(_ size: CGFloat) -> Font { .custom("CoveredByYourGrace", size: size) }
  static func cond(_ size: CGFloat) -> Font { .custom("BarlowCondensed-Bold", size: size) }
  static func ui(_ size: CGFloat) -> Font { .custom("Barlow-SemiBold", size: size) }
  static func soft(_ size: CGFloat) -> Font { .custom("Barlow-Medium", size: size) }
}
