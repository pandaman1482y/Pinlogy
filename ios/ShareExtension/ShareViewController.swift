import UIKit
import Social
import UniformTypeIdentifiers

/// iOS Share Extension 本体。
/// Xcode で Share Extension ターゲットを追加し、このファイルをターゲットへ含めてください。
class ShareViewController: SLComposeServiceViewController {
  private let appGroupId = "group.com.pinlogy.shared"
  private let pendingKey = "pinlogy.pending_share"

  override func isContentValid() -> Bool {
    return true
  }

  override func didSelectPost() {
    Task {
      let payload = await collectPayload()
      persist(payload)
      await openHostApp()
      self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
  }

  override func configurationItems() -> [Any]! {
    return []
  }

  private func collectPayload() async -> [String: Any] {
    var payload: [String: Any] = [
      "title": contentText?.isEmpty == false ? contentText! : "共有された投稿",
      "service": "その他",
    ]
    var imagePaths: [String] = []
    var texts: [String] = []
    var urlString: String?

    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      return payload
    }

    for item in items {
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            urlString = url.absoluteString
          }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            texts.append(text)
          }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          if let saved = await saveImage(provider: provider) {
            imagePaths.append(saved)
          }
        }
      }
    }

    if let contentText, !contentText.isEmpty {
      texts.insert(contentText, at: 0)
    }

    let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if urlString == nil, let first = joined.split(whereSeparator: \.isWhitespace).first,
       first.hasPrefix("http") {
      urlString = String(first)
    }

    if let urlString {
      payload["url"] = urlString
      payload["service"] = guessService(urlString)
    }
    if !joined.isEmpty {
      payload["text"] = joined
    }
    if !imagePaths.isEmpty {
      payload["imagePaths"] = imagePaths
    }
    if payload["title"] == nil {
      payload["title"] = urlString ?? "共有された投稿"
    }
    return payload
  }

  private func saveImage(provider: NSItemProvider) async -> String? {
    do {
      let item = try await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
      let data: Data?
      if let url = item as? URL {
        data = try Data(contentsOf: url)
      } else if let image = item as? UIImage {
        data = image.jpegData(compressionQuality: 0.9)
      } else if let raw = item as? Data {
        data = raw
      } else {
        data = nil
      }
      guard let data else { return nil }
      return writeToAppGroup(data: data, ext: "jpg")
    } catch {
      return nil
    }
  }

  private func saveFile(provider: NSItemProvider, typeId: String, ext: String) async -> String? {
    do {
      let item = try await provider.loadItem(forTypeIdentifier: typeId)
      if let url = item as? URL {
        let data = try Data(contentsOf: url)
        return writeToAppGroup(data: data, ext: ext)
      }
      if let data = item as? Data {
        return writeToAppGroup(data: data, ext: ext)
      }
      return nil
    } catch {
      return nil
    }
  }

  private func writeToAppGroup(data: Data, ext: String) -> String? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else {
      return nil
    }
    let dir = container.appendingPathComponent("Inbox", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
    do {
      try data.write(to: file)
      return file.path
    } catch {
      return nil
    }
  }

  private func persist(_ payload: [String: Any]) {
    guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
      defaults.set(data, forKey: pendingKey)
      defaults.synchronize()
    }
  }

  private func openHostApp() async {
    guard let url = URL(string: "pinlogy://share"), let extensionContext else { return }
    await withCheckedContinuation { continuation in
      extensionContext.open(url) { _ in
        continuation.resume()
      }
    }
  }

  private func guessService(_ raw: String) -> String {
    let hay = raw.lowercased()
    if hay.contains("instagram.com") { return "Instagram" }
    if hay.contains("tiktok.com") { return "TikTok" }
    if hay.contains("youtube.com") || hay.contains("youtu.be") { return "YouTube" }
    return "URL"
  }
}
