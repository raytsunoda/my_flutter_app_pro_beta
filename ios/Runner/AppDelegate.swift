import Flutter
import UIKit
import UserNotifications
import awesome_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    SwiftAwesomeNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Compatibility shim for awesome_notifications 0.10.1 under UIScene.
    // Re-evaluate and remove this when upgrading the plugin.
    if UNUserNotificationCenter.current().delegate == nil {
      NotificationCenter.default.post(
        name: UIApplication.didFinishLaunchingNotification,
        object: UIApplication.shared
      )
    }
  }
}
