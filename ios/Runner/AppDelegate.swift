import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    ScheduleDeepLinkRelay.shared.attach(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}

final class ScheduleDeepLinkRelay {
  static let shared = ScheduleDeepLinkRelay()
  private let name = "jetlag_guide/deep_link"
  private var channel: FlutterMethodChannel?
  private var pending: String?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialLink" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pending)
      self?.pending = nil
    }
    self.channel = channel
  }

  func stash(_ url: URL) {
    guard url.scheme == "jetlagguide" else { return }
    pending = url.absoluteString
  }

  func emit(_ url: URL) {
    guard url.scheme == "jetlagguide" else { return }
    let link = url.absoluteString
    guard let channel else {
      pending = link
      return
    }
    channel.invokeMethod("onLink", arguments: link)
  }
}
