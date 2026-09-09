import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.pinlogy/share"
  private let appGroupId = "group.com.pinlogy.pinlogy.shared"
  private let pendingKey = "pinlogy.pending_share"
  private let pendingQueueKey = "pinlogy.pending_share_queue_v1"
  private let backendUrlKey = "pinlogy.share_backend_url"
  private let backendAnonKey = "pinlogy.share_backend_anon_key"
  private let notificationEnabledKey = "pinlogy.share_notification_enabled"
  private let notificationTokenKey = "pinlogy.share_notification_token"
  private var methodChannel: FlutterMethodChannel?
  private var setupAttempts = 0
  private var dartReady = false
  private var intakeBackgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return .portrait
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "PinlogyMapKit") {
      registrar.register(
        PinlogyMapKitViewFactory(messenger: registrar.messenger()),
        withId: "com.pinlogy/mapkit"
      )
    }
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // FCM token取得より前にAPNs登録を明示し、共有直後のバックグラウンド
    // 解析ジョブにも通知tokenを載せられるようにする。
    application.registerForRemoteNotifications()
    setupShareChannel()
    return launched
  }

  private func setupShareChannel() {
    setupAttempts += 1
    guard
      let controller = window?.rootViewController as? FlutterViewController
    else {
      if setupAttempts < 30 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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
        self.dartReady = true
        result(self.consumePendingShares())
      case "configureBackgroundIntake":
        guard
          let values = call.arguments as? [String: Any],
          let defaults = UserDefaults(suiteName: self.appGroupId)
        else {
          result(false)
          return
        }
        if let value = values["supabaseUrl"] as? String, !value.isEmpty {
          defaults.set(value, forKey: self.backendUrlKey)
        }
        if let value = values["supabaseAnonKey"] as? String, !value.isEmpty {
          defaults.set(value, forKey: self.backendAnonKey)
        }
        if let value = values["notificationEnabled"] as? Bool {
          defaults.set(value, forKey: self.notificationEnabledKey)
        }
        if let value = values["notificationToken"] as? String, !value.isEmpty {
          defaults.set(value, forKey: self.notificationTokenKey)
        }
        defaults.synchronize()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    endIntakeBackgroundTask(application)
    dispatchPendingShareIfReady()
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    guard intakeBackgroundTask == .invalid else { return }
    // 共有直後に閉じても、Dartが解析ジョブをサーバーへ渡し終えるまでの
    // 短い猶予を確保する。実際の画像取得・解析はサーバー側で継続する。
    intakeBackgroundTask = application.beginBackgroundTask(withName: "PinlogyShareIntake") {
      self.endIntakeBackgroundTask(application)
    }
  }

  private func endIntakeBackgroundTask(_ application: UIApplication) {
    guard intakeBackgroundTask != .invalid else { return }
    application.endBackgroundTask(intakeBackgroundTask)
    intakeBackgroundTask = .invalid
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "pinlogy" {
      dispatchPendingShareIfReady()
      return true
    }
    return super.application(app, open: url, options: options)
  }

  private func dispatchPendingShareIfReady() {
    guard dartReady, let methodChannel else { return }
    let payloads = consumePendingShares()
    if !payloads.isEmpty {
      methodChannel.invokeMethod("onShared", arguments: payloads)
    }
  }

  private func consumePendingShares() -> [[String: Any]] {
    guard let defaults = UserDefaults(suiteName: appGroupId) else { return [] }
    var payloads: [[String: Any]] = []
    if
      let data = defaults.data(forKey: pendingQueueKey),
      let object = try? JSONSerialization.jsonObject(with: data),
      let queue = object as? [[String: Any]]
    {
      payloads.append(contentsOf: queue)
    }
    if
      let data = defaults.data(forKey: pendingKey),
      let object = try? JSONSerialization.jsonObject(with: data),
      let legacy = object as? [String: Any]
    {
      payloads.append(legacy)
    }
    defaults.removeObject(forKey: pendingQueueKey)
    defaults.removeObject(forKey: pendingKey)
    defaults.synchronize()
    return payloads
  }
}
