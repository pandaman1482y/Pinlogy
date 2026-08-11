import UIKit
import UniformTypeIdentifiers

/// iOS Share Extension 本体。
/// 共有元アプリ内では保存だけを行い、詳細編集と解析はPinlogy本体へ引き継ぐ。
final class ShareViewController: UIViewController {
  private let appGroupId = "group.com.pinlogy.shared"
  private let pendingKey = "pinlogy.pending_share"
  private let titleLabel = UILabel()
  private let messageLabel = UILabel()
  private let saveButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)
  private let activityIndicator = UIActivityIndicatorView(style: .medium)

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
  }

  private func configureView() {
    view.backgroundColor = .systemBackground

    titleLabel.text = "Pinlogyに保存"
    titleLabel.font = .preferredFont(forTextStyle: .title2)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textAlignment = .center

    messageLabel.text = "投稿を受信箱へ保存します。\nPinlogyを開くと、AI解析と場所候補の確認が始まります。"
    messageLabel.font = .preferredFont(forTextStyle: .body)
    messageLabel.adjustsFontForContentSizeCategory = true
    messageLabel.textColor = .secondaryLabel
    messageLabel.textAlignment = .center
    messageLabel.numberOfLines = 0

    saveButton.configuration = .filled()
    saveButton.configuration?.title = "Pinlogyに保存"
    saveButton.configuration?.cornerStyle = .large
    saveButton.addTarget(self, action: #selector(saveSharedPost), for: .touchUpInside)

    cancelButton.setTitle("キャンセル", for: .normal)
    cancelButton.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)

    activityIndicator.hidesWhenStopped = true

    let actions = UIStackView(arrangedSubviews: [saveButton, cancelButton])
    actions.axis = .vertical
    actions.spacing = 8

    let stack = UIStackView(arrangedSubviews: [
      titleLabel,
      messageLabel,
      activityIndicator,
      actions,
    ])
    stack.axis = .vertical
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
      saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
    ])
  }

  @objc private func saveSharedPost() {
    setBusy(true)
    Task {
      let payload = await collectPayload()
      guard persist(payload) else {
        await MainActor.run {
          self.setBusy(false)
          self.messageLabel.text = "保存できませんでした。Pinlogyと共有機能のApp Group設定を確認して、もう一度お試しください。"
          self.messageLabel.textColor = .systemRed
        }
        return
      }
      await MainActor.run {
        self.activityIndicator.stopAnimating()
        self.titleLabel.text = "保存しました"
        self.messageLabel.text = "Pinlogyを開くと、受信箱から続けられます。"
        self.messageLabel.textColor = .secondaryLabel
        self.saveButton.isHidden = true
        self.cancelButton.isHidden = true
      }
      try? await Task.sleep(nanoseconds: 700_000_000)
      self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
  }

  @objc private func cancelShare() {
    extensionContext?.cancelRequest(withError: NSError(
      domain: "com.pinlogy.share",
      code: NSUserCancelledError
    ))
  }

  private func setBusy(_ busy: Bool) {
    saveButton.isEnabled = !busy
    cancelButton.isEnabled = !busy
    busy ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
  }

  private func collectPayload() async -> [String: Any] {
    var payload: [String: Any] = [
      "title": "共有された投稿",
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
    payload["title"] = texts.first(where: {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) ?? urlString ?? "共有された投稿"
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

  private func persist(_ payload: [String: Any]) -> Bool {
    guard
      let defaults = UserDefaults(suiteName: appGroupId),
      let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
    else {
      return false
    }
    defaults.set(data, forKey: pendingKey)
    defaults.synchronize()
    return defaults.data(forKey: pendingKey) == data
  }

  private func guessService(_ raw: String) -> String {
    let hay = raw.lowercased()
    if hay.contains("instagram.com") { return "Instagram" }
    if hay.contains("tiktok.com") { return "TikTok" }
    if hay.contains("youtube.com") || hay.contains("youtu.be") { return "YouTube" }
    return "URL"
  }
}
