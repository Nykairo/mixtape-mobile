// Mixtape's widgets on the iPhone, the same ones as on Android (Widgets.kt there): the cassette, now
// playing, the cover, the mini player (on the lock screen here) and my tapes. They're drawn from what
// the app leaves in the App Group; their keys work right on the home screen from iOS 17 on, before
// that a tap opens Mixtape.

import SwiftUI
import WidgetKit

@main
struct MixtapeWidgets: WidgetBundle {
  var body: some Widget {
    CassetteWidget()
    NowPlayingWidget()
    CoverWidget()
    TapesWidget()
    if #available(iOS 16.0, *) {
      MiniWidget()
    }
  }
}

// ---------------------------------------------------------------- what they show

struct MixEntry: TimelineEntry {
  let date: Date
  let song: Song?
  let shelf: [ShelfTape]
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> MixEntry {
    MixEntry(date: Date(), song: .sample, shelf: ShelfTape.samples)
  }

  func getSnapshot(in context: Context, completion: @escaping (MixEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : now())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<MixEntry>) -> Void) {
    // the app says when something changes, so no schedule of their own
    completion(Timeline(entries: [now()], policy: .never))
  }

  private func now() -> MixEntry {
    MixEntry(date: Date(), song: Shared.song(), shelf: Shared.shelf())
  }
}

// ---------------------------------------------------------------- bits they share

extension View {
  /// The widget's background, the way each iOS wants it.
  @ViewBuilder
  func widgetBackground(_ color: Color) -> some View {
    if #available(iOS 17.0, *) {
      containerBackground(for: .widget) { color }
    } else {
      background(color)
    }
  }

  @ViewBuilder
  func orangeBar() -> some View {
    if #available(iOS 15.0, *) {
      tint(Deck.orange)
    } else {
      accentColor(Deck.orange)
    }
  }
}

extension WidgetConfiguration {
  /// Drawn to the edges (iOS 17 would keep a margin free).
  func edgeToEdge() -> some WidgetConfiguration {
    if #available(iOS 17.0, *) {
      return contentMarginsDisabled()
    } else {
      return self
    }
  }
}

/// A key on a widget: from iOS 17 on it does its thing right there, before that the widget just opens
/// Mixtape.
struct Key<Face: View>: View {
  var what: String
  @ViewBuilder var label: () -> Face

  var body: some View {
    if #available(iOS 17.0, *) {
      Button(intent: WidgetKey(what)) {
        label()
      }
      .buttonStyle(.plain)
    } else {
      label()
    }
  }
}

struct Glyph: View {
  var name: String
  var size: CGFloat
  var color: Color

  var body: some View {
    Image(systemName: name)
      .font(.system(size: size, weight: .bold))
      .foregroundColor(color)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
  }
}

/// Play or pause, on Mixtape's orange key.
struct PlayKey: View {
  var playing: Bool
  var size: CGFloat

  var body: some View {
    ZStack {
      Circle().fill(Deck.orange)
      Image(systemName: playing ? "pause.fill" : "play.fill")
        .font(.system(size: size * 0.4, weight: .heavy))
        .foregroundColor(Deck.back)
        .offset(x: playing ? 0 : size * 0.04)
    }
    .frame(width: size, height: size)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
  }
}

/// The song's cover, or Mixtape's own when there's none.
struct CoverSquare: View {
  var image: UIImage?

  var body: some View {
    if let image = image {
      Image(uiImage: image).resizable().scaledToFill()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
    } else {
      ZStack {
        Deck.raised
        Image(systemName: "music.note")
          .font(.system(size: 30, weight: .semibold))
          .foregroundColor(Deck.cream.opacity(0.45))
      }
    }
  }
}

/// How long, as 3:07.
func clock(_ seconds: Double) -> String {
  let s = max(0, Int(seconds.rounded(.down)))
  return "\(s / 60):\(String(format: "%02d", s % 60))"
}

/// How far into the song: a bar that moves by itself while it plays (iOS 16 on), and the time.
struct Along: View {
  var song: Song

  var body: some View {
    let end = song.started.addingTimeInterval(max(1, song.duration))
    VStack(spacing: 3) {
      bar(end)
      HStack {
        time(end)
        Spacer()
        Text(song.duration > 0 ? clock(song.duration) : "")
      }
      .font(Deck.soft(10.5))
      .foregroundColor(Deck.muted)
    }
  }

  @ViewBuilder
  private func bar(_ end: Date) -> some View {
    if #available(iOS 16.0, *) {
      if song.playing && song.duration > 0 && end > Date() {
        ProgressView(timerInterval: song.started...end, countsDown: false) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
        .progressViewStyle(.linear)
        .orangeBar()
      } else {
        still
      }
    } else {
      still
    }
  }

  private var still: some View {
    ProgressView(value: min(song.position, max(1, song.duration)), total: max(1, song.duration))
      .progressViewStyle(.linear)
      .orangeBar()
  }

  @ViewBuilder
  private func time(_ end: Date) -> some View {
    if #available(iOS 16.0, *) {
      if song.playing && end > Date() {
        Text(timerInterval: song.started...end, countsDown: false)
      } else {
        Text(clock(song.position))
      }
    } else {
      Text(clock(song.position))
    }
  }
}

// ---------------------------------------------------------------- the cassette

struct CassetteWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MixtapeCassette", provider: Provider()) { entry in
      CassetteView(entry: entry)
    }
    .configurationDisplayName("Cassette")
    .description("The song on a little cassette: the cover glued on its label, the keys in its head.")
    .supportedFamilies([.systemMedium])
    .edgeToEdge()
  }
}

struct CassetteView: View {
  var entry: MixEntry

  var body: some View {
    let song = entry.song
    let look = song?.look ?? .plain
    let glyph = look.shell.light ? Deck.back : Deck.cream
    CassetteArt(look: look, title: song?.title ?? "Mixtape", artist: song?.artist ?? "press play", cover: song?.cover,
                along: song?.along ?? 0) {
      HStack(spacing: 0) {
        Key(what: "previous") { Glyph(name: "backward.fill", size: 13, color: glyph) }
        Key(what: song?.playing == true ? "pause" : "play") { PlayKey(playing: song?.playing == true, size: 26) }
        Key(what: "next") { Glyph(name: "forward.fill", size: 13, color: glyph) }
      }
    }
    .padding(8)
    .widgetBackground(Deck.back)
  }
}

// ---------------------------------------------------------------- now playing

struct NowPlayingWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MixtapeNowPlaying", provider: Provider()) { entry in
      NowPlayingView(entry: entry)
    }
    .configurationDisplayName("Now playing")
    .description("The cover big, with like, shuffle and the keys.")
    .supportedFamilies([.systemMedium])
    .edgeToEdge()
  }
}

struct NowPlayingView: View {
  var entry: MixEntry

  var body: some View {
    let song = entry.song
    let playing = song?.playing == true
    HStack(spacing: 14) {
      CoverSquare(image: song?.cover)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
      VStack(alignment: .leading, spacing: 2) {
        Text("MIXTAPE").font(Deck.cond(11)).kerning(1.8).foregroundColor(Deck.orange)
        Text(song?.title ?? "Nothing playing")
          .font(Deck.ui(16)).foregroundColor(Deck.cream).lineLimit(1)
        Text(song.map { $0.artist } ?? "Press play in Mixtape")
          .font(Deck.soft(13)).foregroundColor(Deck.muted).lineLimit(1)
        Spacer(minLength: 4)
        if let song = song {
          Along(song: song)
        }
        HStack(spacing: 0) {
          Key(what: "like") {
            Glyph(name: song?.liked == true ? "heart.fill" : "heart", size: 15, color: song?.liked == true ? Deck.orange : Deck.cream)
          }
          Key(what: "previous") { Glyph(name: "backward.fill", size: 15, color: Deck.cream) }
          Key(what: playing ? "pause" : "play") { PlayKey(playing: playing, size: 34) }
          Key(what: "next") { Glyph(name: "forward.fill", size: 15, color: Deck.cream) }
          Key(what: "shuffle") {
            Glyph(name: "shuffle", size: 15, color: song?.shuffle == true ? Deck.orange : Deck.cream)
          }
        }
        .frame(height: 36)
      }
    }
    .padding(14)
    .widgetBackground(Deck.back)
  }
}

// ---------------------------------------------------------------- the cover

struct CoverWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MixtapeCover", provider: Provider()) { entry in
      CoverView(entry: entry)
    }
    .configurationDisplayName("Cover")
    .description("Just the cover and a play key.")
    .supportedFamilies([.systemSmall])
    .edgeToEdge()
  }
}

struct CoverView: View {
  var entry: MixEntry

  var body: some View {
    let song = entry.song
    let playing = song?.playing == true
    ZStack(alignment: .bottom) {
      CoverSquare(image: song?.cover)
      LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.78)]),
                     startPoint: .center, endPoint: .bottom)
      HStack(alignment: .bottom, spacing: 6) {
        VStack(alignment: .leading, spacing: 1) {
          Text(song?.title ?? "Mixtape").font(Deck.ui(13)).foregroundColor(.white).lineLimit(1)
          Text(song.map { $0.artist } ?? "Press play").font(Deck.soft(11)).foregroundColor(Color.white.opacity(0.75)).lineLimit(1)
        }
        Spacer(minLength: 0)
        Key(what: playing ? "pause" : "play") { PlayKey(playing: playing, size: 32) }
          .frame(width: 36, height: 36)
      }
      .padding(10)
    }
    .widgetBackground(Deck.back)
  }
}

// ---------------------------------------------------------------- my tapes

struct TapesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MixtapeTapes", provider: Provider()) { entry in
      TapesView(entry: entry)
    }
    .configurationDisplayName("My tapes")
    .description("Your tapes as little cassettes: one tap plays one.")
    .supportedFamilies([.systemMedium, .systemLarge])
    .edgeToEdge()
  }
}

struct TapesView: View {
  @Environment(\.widgetFamily) private var family
  var entry: MixEntry

  var body: some View {
    let rows = family == .systemLarge ? 2 : 1
    let tapes = Array(entry.shelf.prefix(rows * 4))
    VStack(alignment: .leading, spacing: 8) {
      Text("MY TAPES").font(Deck.cond(12)).kerning(1.8).foregroundColor(Deck.orange)
      if tapes.isEmpty {
        Spacer(minLength: 0)
        Text("Your tapes show up here")
          .font(Deck.hand(19)).foregroundColor(Deck.muted)
          .frame(maxWidth: .infinity)
        Spacer(minLength: 0)
      } else {
        VStack(spacing: 10) {
          ForEach(0..<rows, id: \.self) { row in
            HStack(spacing: 10) {
              ForEach(0..<4, id: \.self) { k in
                if row * 4 + k < tapes.count {
                  Key(what: "tape:\(tapes[row * 4 + k].id)") {
                    LittleTape(tape: tapes[row * 4 + k]).contentShape(Rectangle())
                  }
                } else {
                  Color.clear
                }
              }
            }
          }
        }
      }
    }
    .padding(14)
    .widgetBackground(Deck.back)
  }
}

// ---------------------------------------------------------------- the mini player, on the lock screen

@available(iOS 16.0, *)
struct MiniWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MixtapeMini", provider: Provider()) { entry in
      MiniView(entry: entry)
    }
    .configurationDisplayName("Mini player")
    .description("The song on the lock screen, with play and pause.")
    .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
  }
}

@available(iOS 16.0, *)
struct MiniView: View {
  @Environment(\.widgetFamily) private var family
  var entry: MixEntry

  var body: some View {
    let song = entry.song
    let playing = song?.playing == true
    switch family {
    case .accessoryInline:
      Label(song?.title ?? "Mixtape", systemImage: playing ? "play.fill" : "music.note")
        .widgetBackground(Color.clear)
    case .accessoryCircular:
      Key(what: playing ? "pause" : "play") {
        ZStack {
          AccessoryWidgetBackground()
          Circle()
            .trim(from: 0, to: song.map { $0.duration > 0 ? min(1, $0.position / $0.duration) : 0 } ?? 0)
            .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(3)
            .widgetAccentable()
          Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .bold))
        }
      }
      .widgetBackground(Color.clear)
    default:
      VStack(alignment: .leading, spacing: 1) {
        Text("MIXTAPE").font(.system(size: 11, weight: .heavy)).kerning(1.2).widgetAccentable()
        Text(song?.title ?? "Nothing playing").font(.headline).lineLimit(1)
        Text(song.map { $0.artist } ?? "Press play in Mixtape").font(.caption).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .widgetBackground(Color.clear)
    }
  }
}
