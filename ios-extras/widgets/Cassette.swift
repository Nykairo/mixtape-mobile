// The cassette the widgets draw, in the colors of the tape that plays: the same one as on Android
// (WidgetArt.kt there), made of SwiftUI shapes.

import SwiftUI

/// Puts a view in a rectangle of its parent (the parent being a ZStack at the cassette's size).
private extension View {
  func placed(_ r: CGRect) -> some View {
    frame(width: max(0, r.width), height: max(0, r.height)).position(x: r.midX, y: r.midY)
  }
}

private struct Trapezoid: Shape {
  var inset: CGFloat // how much narrower the top is, on each side, as a part of the width

  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.minX + r.width * inset, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - r.width * inset, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
    p.closeSubpath()
    return p
  }
}

struct Heart: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let cx = r.midX, s = min(r.width, r.height) / 2, cy = r.midY - s * 0.05
    p.move(to: CGPoint(x: cx, y: cy + s * 0.9))
    p.addCurve(to: CGPoint(x: cx, y: cy - s * 0.35), control1: CGPoint(x: cx - s * 1.4, y: cy),
               control2: CGPoint(x: cx - s * 0.9, y: cy - s * 1.1))
    p.addCurve(to: CGPoint(x: cx, y: cy + s * 0.9), control1: CGPoint(x: cx + s * 0.9, y: cy - s * 1.1),
               control2: CGPoint(x: cx + s * 1.4, y: cy))
    p.closeSubpath()
    return p
  }
}

/// The stripes across the middle of the label, in one of the tape's stripe styles.
private struct Stripes: View {
  var look: TapeColors

  var body: some View {
    GeometryReader { g in
      let s = look.stripes.map(\.color)
      let h = g.size.height
      switch look.stripeStyle {
      case "none":
        Color.clear
      case "band":
        VStack(spacing: 0) {
          s[0].frame(height: h * 0.62)
          Spacer(minLength: 0)
        }
      case "lines":
        ZStack(alignment: .topLeading) {
          ForEach(0..<3, id: \.self) { k in
            s[k % s.count].frame(height: h * 0.12).offset(y: h * (0.12 + CGFloat(k) * 0.3))
          }
        }
      case "fade":
        VStack(spacing: 0) {
          LinearGradient(gradient: Gradient(colors: [s[0], s[min(2, s.count - 1)]]), startPoint: .leading, endPoint: .trailing)
            .frame(height: h * 0.7)
          Spacer(minLength: 0)
        }
      default:
        VStack(spacing: 0) {
          s[0].frame(height: h * 0.46)
          s[1 % s.count].frame(height: h * 0.32)
          s[2 % s.count].frame(height: h * 0.22)
        }
      }
    }
  }
}

/// A reel's hub: a ring with six teeth.
private struct Hub: View {
  var color: Color

  var body: some View {
    GeometryReader { g in
      let r = min(g.size.width, g.size.height) / 2
      ZStack {
        Circle().fill(color)
        Circle().fill(Color(.sRGB, red: 0x12 / 255.0, green: 0x0E / 255.0, blue: 0x0B / 255.0, opacity: 1))
          .frame(width: r * 1.24, height: r * 1.24)
        ForEach(0..<6, id: \.self) { k in
          Rectangle().fill(color)
            .frame(width: r * 0.28, height: r * 0.2)
            .rotationEffect(.degrees(Double(k) * 60 + 15))
            .offset(x: cos((Double(k) * 60 + 15) * .pi / 180) * r * 0.5, y: sin((Double(k) * 60 + 15) * .pi / 180) * r * 0.5)
        }
      }
      .frame(width: r * 2, height: r * 2)
    }
  }
}

/// The window with the two reels, wound as far as the music is into the tape.
private struct Window: View {
  var look: TapeColors
  var along: Double

  var body: some View {
    GeometryReader { g in
      let w = g.size.width, h = g.size.height
      let hubR = h * 0.24, smallest = hubR * 1.25, biggest = h * 1.05
      let tape = look.tape
      ZStack {
        Color(.sRGB, red: 0x0E / 255.0, green: 0x0B / 255.0, blue: 0x09 / 255.0, opacity: 1)
        ForEach(0..<2, id: \.self) { k in
          let wound = k == 0 ? 1 - along : along
          let r = smallest + (biggest - smallest) * wound
          let x = k == 0 ? w * 0.2 : w * 0.8
          Circle()
            .fill(RadialGradient(
              gradient: Gradient(stops: [
                .init(color: tape.mixed(with: .black, 0.5).color, location: 0),
                .init(color: tape.color, location: 0.55),
                .init(color: tape.mixed(with: .white, 0.08).color, location: 0.92),
                .init(color: tape.mixed(with: .black, 0.4).color, location: 1),
              ]),
              center: .center, startRadius: 0, endRadius: r))
            .frame(width: r * 2, height: r * 2)
            .position(x: x, y: h / 2)
          Hub(color: look.hub.color)
            .frame(width: hubR * 2, height: hubR * 2)
            .position(x: x, y: h / 2)
        }
        // the window's glass
        LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0)]),
                       startPoint: .topLeading, endPoint: UnitPoint(x: 0.4, y: 1))
      }
      .clipShape(Capsule())
    }
  }
}

/// A cassette as big as fits, in a tape's colors: its label with the song written on it by hand, the
/// cover glued on like a photo, the reels, the screws, and the head at the bottom where [keys] go.
struct CassetteArt<Keys: View>: View {
  var look: TapeColors
  var title: String
  var artist: String
  var cover: UIImage?
  var along: Double
  var photo = true
  @ViewBuilder var keys: () -> Keys

  var body: some View {
    GeometryReader { g in
      let cw = min(g.size.width, g.size.height * 1.574), ch = cw / 1.574
      let corner = cw * 0.05
      let label = CGRect(x: cw * 0.06, y: ch * 0.075, width: cw * 0.88, height: ch * 0.63)
      let lh = label.height
      let wcy = label.minY + lh * 0.735
      let window = CGRect(x: cw * 0.23, y: wcy - ch * 0.1025, width: cw * 0.54, height: ch * 0.205)
      let ps = lh * 0.46
      let photoSpot = CGRect(x: label.minX + cw * 0.075, y: label.minY + lh * 0.075, width: ps, height: ps)
      let textLeft = photo ? photoSpot.maxX + cw * 0.035 : label.minX + cw * 0.05
      let titleRight = label.maxX - lh * 0.13 * 1.6 - cw * 0.02
      let head = CGRect(x: cw * 0.155, y: ch * 0.775, width: cw * 0.69, height: ch * 0.225)
      let shellTop = look.shell.mixed(with: .white, 0.12).color, shellLow = look.shell.mixed(with: .black, 0.18).color
      let alpha = max(150.0 / 255, look.shellAlpha)
      ZStack {
        Group {
          RoundedRectangle(cornerRadius: corner).fill(Color.black.opacity(0.45))
            .blur(radius: max(1, cw * 0.02))
            .placed(CGRect(x: cw * 0.01, y: ch * 0.05, width: cw * 0.98, height: ch * 0.975))
          RoundedRectangle(cornerRadius: corner)
            .fill(LinearGradient(gradient: Gradient(colors: [shellTop, shellLow]), startPoint: .top, endPoint: .bottom))
            .opacity(alpha)
          RoundedRectangle(cornerRadius: corner)
            .strokeBorder(Color.white.opacity(0.14), lineWidth: max(1, cw * 0.006))
        }
        // the label, its stripes, the "A" in the corner, the window
        Group {
          RoundedRectangle(cornerRadius: cw * 0.016)
            .fill(LinearGradient(gradient: Gradient(colors: [look.paper.mixed(with: .white, 0.08).color,
                                                             look.paper.mixed(with: .black, 0.06).color]),
                                 startPoint: .top, endPoint: .bottom))
            .placed(label)
          Stripes(look: look)
            .placed(CGRect(x: label.minX, y: label.minY + lh * 0.40, width: label.width, height: lh * 0.185))
          sideA(label)
          Window(look: look, along: along).placed(window)
        }
        // the photo, and the song by hand on the label's lines
        Group {
          if photo {
            glued(photoSpot)
          }
          Text(title.isEmpty ? "Mixtape" : title)
            .font(Deck.hand(lh * 0.2))
            .foregroundColor(look.ink.color)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: max(1, titleRight - textLeft), alignment: .leading)
            .position(x: (textLeft + titleRight) / 2, y: label.minY + lh * 0.17)
          Text(artist)
            .font(Deck.hand(lh * 0.125))
            .foregroundColor(look.ink.color.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: max(1, label.maxX - cw * 0.035 - textLeft), alignment: .leading)
            .position(x: (textLeft + label.maxX - cw * 0.035) / 2, y: label.minY + lh * 0.325)
        }
        // the screws, and the head at the bottom where the keys are
        Group {
          if look.screws {
            screws(cw, ch)
          }
          Trapezoid(inset: 0.055 / 0.69)
            .fill(look.shell.light ? look.shell.mixed(with: .black, 0.1).color : look.shell.mixed(with: .white, 0.08).color)
            .placed(head)
          keys()
            .placed(CGRect(x: cw * 0.21, y: ch * 0.775, width: cw * 0.58, height: ch * 0.225))
        }
      }
      .frame(width: cw, height: ch)
      .position(x: g.size.width / 2, y: g.size.height / 2)
    }
  }

  private func sideA(_ label: CGRect) -> some View {
    let size = label.height * 0.13
    let box = CGRect(x: label.maxX - size * 1.6, y: label.minY + label.height * 0.06, width: size, height: size)
    let ink = look.ink.mixed(with: look.paper, 0.35).color
    return ZStack {
      Rectangle().strokeBorder(ink, lineWidth: max(1, size * 0.08))
      Text("A").font(.system(size: size * 0.8, weight: .bold)).foregroundColor(ink)
    }
    .placed(box)
  }

  /// The cover glued on the label's left end, a little crooked, with a strip of tape over it.
  private func glued(_ spot: CGRect) -> some View {
    let s = spot.width, inset = s * 0.07
    return ZStack {
      Rectangle().fill(Color(.sRGB, red: 0xFD / 255.0, green: 0xFB / 255.0, blue: 0xF6 / 255.0, opacity: 1))
        .shadow(color: Color.black.opacity(0.22), radius: max(1, s * 0.04), x: s * 0.03, y: s * 0.05)
      Group {
        if let cover = cover {
          Image(uiImage: cover).resizable().scaledToFill()
        } else {
          ZStack {
            Deck.raised
            Image(systemName: "music.note").resizable().scaledToFit()
              .foregroundColor(Deck.cream.opacity(0.6)).padding(s * 0.18)
          }
        }
      }
      .frame(width: s - inset * 2, height: s - inset * 2)
      .clipped()
      Rectangle().fill(Color(.sRGB, red: 1, green: 0xF6 / 255.0, blue: 0xD6 / 255.0, opacity: 0.55))
        .frame(width: s * 0.4, height: s * 0.15)
        .rotationEffect(.degrees(3))
        .offset(y: -s / 2)
    }
    .frame(width: s, height: s)
    .rotationEffect(.degrees(-4))
    .placed(spot)
  }

  private func screws(_ cw: CGFloat, _ ch: CGFloat) -> some View {
    let r = cw * 0.012
    let spots = [(cw * 0.032, ch * 0.055), (cw * 0.968, ch * 0.055), (cw * 0.032, ch * 0.93), (cw * 0.968, ch * 0.93)]
    return ZStack {
      ForEach(0..<4, id: \.self) { k in
        ZStack {
          Circle().fill(look.screw.color)
          Rectangle().fill(Color.black.opacity(0.4)).frame(width: r * 1.6, height: max(1, r * 0.3)).rotationEffect(.degrees(45))
        }
        .frame(width: r * 2, height: r * 2)
        .position(x: spots[k].0, y: spots[k].1)
      }
    }
  }
}

extension CassetteArt where Keys == EmptyView {
  init(look: TapeColors, title: String, artist: String, cover: UIImage?, along: Double, photo: Bool = true) {
    self.init(look: look, title: title, artist: artist, cover: cover, along: along, photo: photo, keys: { EmptyView() })
  }
}

/// A small cassette for the shelf, in a tape's colors, its name written under it.
struct LittleTape: View {
  var tape: ShelfTape

  var body: some View {
    VStack(spacing: 2) {
      GeometryReader { g in
        let cw = min(g.size.width, g.size.height * 1.574), ch = cw / 1.574
        let label = CGRect(x: cw * 0.06, y: ch * 0.08, width: cw * 0.88, height: ch * 0.62)
        let wcy = label.minY + label.height * 0.735
        ZStack {
          RoundedRectangle(cornerRadius: cw * 0.06).fill(Color.black.opacity(0.35)).blur(radius: max(1, cw * 0.03))
            .placed(CGRect(x: 1, y: ch * 0.06, width: cw - 2, height: ch * 0.97))
          RoundedRectangle(cornerRadius: cw * 0.06)
            .fill(LinearGradient(gradient: Gradient(colors: [tape.look.shell.mixed(with: .white, 0.12).color,
                                                             tape.look.shell.mixed(with: .black, 0.18).color]),
                                 startPoint: .top, endPoint: .bottom))
          RoundedRectangle(cornerRadius: cw * 0.02).fill(tape.look.paper.color).placed(label)
          Stripes(look: tape.look)
            .placed(CGRect(x: label.minX, y: label.minY + label.height * 0.40, width: label.width, height: label.height * 0.185))
          Window(look: tape.look, along: 0.35)
            .placed(CGRect(x: cw * 0.25, y: wcy - ch * 0.1, width: cw * 0.5, height: ch * 0.2))
          if tape.liked {
            Heart().fill(Deck.orange)
              .placed(CGRect(x: label.minX + label.height * 0.08, y: label.minY + label.height * 0.06,
                             width: label.height * 0.32, height: label.height * 0.32))
          }
          Trapezoid(inset: 0.05 / 0.66)
            .fill(tape.look.shell.light ? tape.look.shell.mixed(with: .black, 0.1).color : tape.look.shell.mixed(with: .white, 0.08).color)
            .placed(CGRect(x: cw * 0.17, y: ch * 0.78, width: cw * 0.66, height: ch * 0.22))
        }
        .frame(width: cw, height: ch)
        .position(x: g.size.width / 2, y: g.size.height / 2)
      }
      Text(tape.liked ? "liked songs" : tape.name)
        .font(Deck.hand(14))
        .foregroundColor(Deck.cream)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
  }
}
