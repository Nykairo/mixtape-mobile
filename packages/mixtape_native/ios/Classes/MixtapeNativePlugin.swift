// The parts of Mixtape that live on the iPhone side: the share sheet, picking a picture (a profile
// picture, or a photo to stick on a tape), and what the home screen widgets show. The widgets read it
// from the App Group the app shares with them (ios-extras/widgets); their keys come back here.

import Flutter
import PhotosUI
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

public class MixtapeNativePlugin: NSObject, FlutterPlugin {
  /// The App Group the app and its widgets share.
  static let group = "group.dev.softwarevault.mixtape"

  private var channel: FlutterMethodChannel?
  private var picking: FlutterResult?
  private var pickingFor = "profile"
  /// A widget key pressed before the app's Dart side was listening: it asks for it with widgetLaunch.
  private var launched: String?
  /// The song whose cover the widgets have.
  private var coverFor = ""

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "mixtape/native", binaryMessenger: registrar.messenger())
    let plugin = MixtapeNativePlugin()
    plugin.channel = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
    // the widgets' keys run in the app (Intents.swift) and say so here
    NotificationCenter.default.addObserver(plugin, selector: #selector(plugin.widgetKey(_:)),
                                           name: Notification.Name("MixtapeWidgetKey"), object: nil)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "share":
      result(share([args["text"] as? String ?? ""]))
    case "shareImage":
      guard let path = args["path"] as? String, let image = UIImage(contentsOfFile: path) else {
        result(false)
        return
      }
      let text = args["text"] as? String ?? ""
      result(share(text.isEmpty ? [image] : [image, text]))
    case "pickPicture":
      pick(args["for"] as? String ?? "profile", result)
    case "widget":
      playing(args)
      result(nil)
    case "shelf":
      keep(call.arguments, as: "shelf")
      result(nil)
    case "widgetLaunch":
      result(launched)
      launched = nil
    case "widgetWaiting":
      result("[]") // a like on an iPhone widget always goes through the app
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ---------------------------------------------------------------- sharing

  /// The share sheet with these on it; false when there's nothing to show it over.
  private func share(_ items: [Any]) -> Bool {
    guard let top = topController() else { return false }
    let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let bubble = sheet.popoverPresentationController { // an iPad shows it as a bubble
      bubble.sourceView = top.view
      bubble.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
      bubble.permittedArrowDirections = []
    }
    top.present(sheet, animated: true)
    return true
  }

  private func topController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let shown = top?.presentedViewController {
      top = shown
    }
    return top
  }

  // ---------------------------------------------------------------- a picture from the phone

  private func pick(_ what: String, _ result: @escaping FlutterResult) {
    guard #available(iOS 14, *) else {
      result(nil)
      return
    }
    guard let top = topController() else {
      result(nil)
      return
    }
    picking?(nil) // one at a time: one that never came back gets nothing
    picking = result
    pickingFor = what
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    top.present(picker, animated: true)
  }

  // ---------------------------------------------------------------- the widgets

  /// What plays, for the widgets: kept in the App Group with the moment it was said (so they count on
  /// from there by themselves), its cover copied next to it.
  private func playing(_ song: [String: Any]) {
    var said = song
    said["at"] = Date().timeIntervalSince1970
    said["art"] = ""
    let id = song["id"] as? String ?? ""
    if let art = song["art"] as? String, !art.isEmpty,
       let box = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group) {
      let cover = box.appendingPathComponent("cover.jpg")
      if id != coverFor || !FileManager.default.fileExists(atPath: cover.path) {
        try? FileManager.default.removeItem(at: cover)
        coverFor = (try? FileManager.default.copyItem(at: URL(fileURLWithPath: art), to: cover)) != nil ? id : ""
      }
      if !coverFor.isEmpty {
        said["art"] = "cover.jpg"
      }
    }
    keep(said, as: "playing")
  }

  /// Keeps something in the App Group as JSON, and has the widgets draw again when it changed.
  private func keep(_ value: Any?, as key: String) {
    guard let value = value, JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let text = String(data: data, encoding: .utf8) else { return }
    let shared = UserDefaults(suiteName: Self.group)
    if shared?.string(forKey: key) == text { return }
    shared?.set(text, forKey: key)
    #if canImport(WidgetKit)
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
    #endif
  }

  /// A key pressed on a widget: play, pause, next, previous, like, shuffle, or tape: and a tape's id.
  @objc private func widgetKey(_ note: Notification) {
    guard let what = note.userInfo?["what"] as? String else { return }
    DispatchQueue.main.async {
      guard let channel = self.channel else {
        self.launched = what
        return
      }
      channel.invokeMethod("widget", arguments: what) { answer in
        // nobody listened yet (the app just started for this key): it waits for widgetLaunch
        if answer is FlutterError || (answer as? NSObject) === FlutterMethodNotImplemented {
          self.launched = what
        }
      }
    }
  }
}

@available(iOS 14, *)
extension MixtapeNativePlugin: PHPickerViewControllerDelegate {
  public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let answer = picking else { return }
    picking = nil
    let what = pickingFor
    guard let item = results.first?.itemProvider, item.canLoadObject(ofClass: UIImage.self) else {
      answer(nil)
      return
    }
    item.loadObject(ofClass: UIImage.self) { object, _ in
      var made: Any? = nil
      if let image = object as? UIImage {
        if what == "tape" {
          made = Pictures.forTape(image)
        } else {
          made = Pictures.profile(image)
        }
      }
      DispatchQueue.main.async {
        answer(made)
      }
    }
  }
}

/// Pictures picked on the phone, made the way the computer makes them.
enum Pictures {
  /// A profile picture (profiles.encode_picture on the computer): the middle square, 256 pixels, on
  /// label paper where it's see-through, a JPEG in base64 of at most 150,000 characters.
  static func profile(_ image: UIImage) -> String? {
    let side: CGFloat = 256
    let size = image.size
    guard size.width >= 8, size.height >= 8 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
      UIColor(red: 0xF1 / 255.0, green: 0xE6 / 255.0, blue: 0xCF / 255.0, alpha: 1).setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
      let k = side / min(size.width, size.height)
      let w = size.width * k, h = size.height * k
      image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
    }
    for quality in [0.86, 0.72, 0.58] {
      if let data = square.jpegData(compressionQuality: CGFloat(quality)) {
        let text = data.base64EncodedString()
        if text.count <= 150_000 {
          return text
        }
      }
    }
    return nil
  }

  /// A photo for a tape (decor.import_picture on the computer): at most 640 pixels long, a PNG when it
  /// really has see-through parts, else a JPEG: {"data": base64, "png": whether it's a PNG}.
  static func forTape(_ image: UIImage) -> [String: Any]? {
    let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    guard px.width >= 1, px.height >= 1 else { return nil }
    let k = min(1, 640 / max(px.width, px.height))
    let fit = CGSize(width: max(1, (px.width * k).rounded()), height: max(1, (px.height * k).rounded()))
    let see = hasHoles(image)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = !see
    let drawn = UIGraphicsImageRenderer(size: fit, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: fit))
    }
    guard let data = see ? drawn.pngData() : drawn.jpegData(compressionQuality: 0.88), data.count <= 2_000_000 else {
      return nil
    }
    return ["data": data.base64EncodedString(), "png": see]
  }

  /// Does the picture really use see-through parts? Looked at on a small grid, not every pixel.
  private static func hasHoles(_ image: UIImage) -> Bool {
    guard let cg = image.cgImage else { return false }
    switch cg.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
      return false
    default:
      break
    }
    let n = 24
    var pixels = [UInt8](repeating: 255, count: n * n * 4)
    let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
      guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      ctx.clear(CGRect(x: 0, y: 0, width: n, height: n))
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
      return true
    }
    guard drawn else { return false }
    for k in stride(from: 3, to: pixels.count, by: 4) where pixels[k] < 250 {
      return true
    }
    return false
  }
}
