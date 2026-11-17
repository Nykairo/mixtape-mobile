// The parts of Mixtape that live on the iPhone side: the share sheet, picking a picture (a profile
// picture, or a photo to stick on a tape), a file or music from the phone, and what the home screen
// widgets show. The widgets read it from the App Group the app shares with them (ios-extras/widgets);
// their keys come back here.

import AVFoundation
import Flutter
import PhotosUI
import SwiftUI // Xcode 26 loses the photo picker's types next to WidgetKit unless SwiftUI is here too
import UIKit
import UniformTypeIdentifiers

public class MixtapeNativePlugin: NSObject, FlutterPlugin {
  /// The App Group the app and its widgets share. Sideloading tools give it a name of their own and say
  /// which in ALTAppGroups.
  static let group: String = {
    if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let first = groups.first {
      return first
    }
    return "group.dev.softwarevault.mixtape"
  }()

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
    case "shareFile":
      guard let path = args["path"] as? String, FileManager.default.fileExists(atPath: path) else {
        result(false)
        return
      }
      result(share([URL(fileURLWithPath: path)]))
    case "pickFile":
      pickFile(result)
    case "pickMusic":
      pickMusic(result)
    case "openedMusic":
      result([Any]()) // nothing opens a file with Mixtape on the iPhone yet: Add music picks them
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

  /// A file from the phone's Files (a library to take in), copied where the app can read it.
  private func pickFile(_ result: @escaping FlutterResult) {
    guard #available(iOS 14, *) else {
      result(nil)
      return
    }
    guard let top = topController() else {
      result(nil)
      return
    }
    picking?(nil)
    picking = result
    pickingFor = "file"
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .plainText, .data], asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    top.present(picker, animated: true)
  }

  /// Songs from the phone's Files, copied where the app can play them: [] when none were picked.
  private func pickMusic(_ result: @escaping FlutterResult) {
    guard #available(iOS 14, *), let top = topController() else {
      result([Any]())
      return
    }
    picking?(nil)
    picking = result
    pickingFor = "music"
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = true
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
    HomeWidgets.redraw()
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

extension MixtapeNativePlugin: UIDocumentPickerDelegate {
  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let answer = picking else { return }
    picking = nil
    if pickingFor == "music" {
      let picked = Array(urls.prefix(300))
      DispatchQueue.global(qos: .userInitiated).async {
        let songs = PhoneMusic.read(picked)
        DispatchQueue.main.async {
          answer(songs)
        }
      }
      return
    }
    guard let from = urls.first else {
      answer(nil)
      return
    }
    // a copy of its own in the app's temporary folder, that stays readable after the picker is gone
    let to = FileManager.default.temporaryDirectory.appendingPathComponent("picked")
    try? FileManager.default.removeItem(at: to)
    let reading = from.startAccessingSecurityScopedResource()
    defer {
      if reading {
        from.stopAccessingSecurityScopedResource()
      }
    }
    answer((try? FileManager.default.copyItem(at: from, to: to)) != nil ? to.path : nil)
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    picking?(pickingFor == "music" ? [Any]() : nil)
    picking = nil
  }
}

/// Music files picked on the phone: what's written inside each one (title, artist, album, length and
/// its cover), the way the computer reads a music folder. They play from the copies the picker made.
enum PhoneMusic {
  static func read(_ urls: [URL]) -> [[String: Any]] {
    tidy()
    return urls.map { song($0) }
  }

  private static func song(_ url: URL) -> [String: Any] {
    let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
    var found: [String: Any] = ["src": "file", "ref": url.path, "title": name.isEmpty ? "Untitled" : name]
    let asset = AVURLAsset(url: url)
    let seconds = CMTimeGetSeconds(asset.duration)
    if seconds.isFinite && seconds > 0 {
      found["dur"] = Int(seconds)
    }
    let tags = asset.commonMetadata
    func text(_ key: AVMetadataKey) -> String? {
      let value = AVMetadataItem.metadataItems(from: tags, withKey: key, keySpace: .common).first?.stringValue
      let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return trimmed.isEmpty ? nil : trimmed
    }
    if let title = text(.commonKeyTitle) { found["title"] = title }
    if let artist = text(.commonKeyArtist) { found["artist"] = artist }
    if let album = text(.commonKeyAlbumName) { found["album"] = album }
    if let data = AVMetadataItem.metadataItems(from: tags, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common).first?.dataValue,
       let art = cover(data) {
      found["art"] = art
    }
    return found
  }

  /// The cover as a small JPEG next to the app's other covers: its path, or nil.
  private static func cover(_ data: Data) -> String? {
    guard let image = UIImage(data: data), image.size.width >= 1, image.size.height >= 1 else { return nil }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("phone-covers")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("\(UUID().uuidString).jpg")
    let k = min(1, 544 / max(image.size.width, image.size.height))
    let size = CGSize(width: max(1, (image.size.width * k).rounded()), height: max(1, (image.size.height * k).rounded()))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    guard let jpeg = small.jpegData(compressionQuality: 0.86), (try? jpeg.write(to: file, options: .atomic)) != nil else { return nil }
    return file.path
  }

  /// Covers and copies from more than a day ago go: the songs they were for left the queue long since.
  private static func tidy() {
    let fm = FileManager.default
    let old = Date().addingTimeInterval(-86_400)
    let inbox = fm.temporaryDirectory.appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "mixtape")-Inbox")
    for folder in [fm.temporaryDirectory.appendingPathComponent("phone-covers"), inbox] {
      let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
      for f in files {
        let when = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        if when < old { try? fm.removeItem(at: f) }
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
