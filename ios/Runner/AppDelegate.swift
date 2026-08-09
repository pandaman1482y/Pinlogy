import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.pinlogy/share"
  private let appGroupId = "group.com.pinlogy.shared"
  private let pendingKey = "pinlogy.pending_share"
  private var methodChannel: FlutterMethodChannel?
  private var setupAttempts = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupShareChannel()
    return launched
  }

  private func setupShareChannel() {
    setupAttempts += 1
    guard
      let controller = window?.rootViewController as? FlutterViewController
    else {
      if setupAttempts < 30 {
        DispatchQueue.main.async { [weak self] in
          self?.setupShareChannel()
        }
      }
      return
    }

    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "getInitialSharedMedia":
        result(self.consumePendingShare())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    if let payload = consumePendingShare() {
      methodChannel?.invokeMethod("onShared", arguments: payload)
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "pinlogy" {
      if let payload = consumePendingShare() {
        methodChannel?.invokeMethod("onShared", arguments: payload)
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }

  private func consumePendingShare() -> [String: Any]? {
    guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
    guard let data = defaults.data(forKey: pendingKey) else { return nil }
    defaults.removeObject(forKey: pendingKey)
    defaults.synchronize()
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let map = object as? [String: Any]
    else {
      return nil
    }
    return map
  }
}
