import UIKit
import Flutter
import awesome_notifications

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Flutterプラグインの自動登録
    GeneratedPluginRegistrant.register(with: self)

    // awesome_notifications 初期化（必要に応じて）
    AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: 'basic_channel',
          channelName: 'Basic Notifications',
          channelDescription: 'Notification channel for basic tests',
          defaultColor: UIColor.systemTeal,
          ledColor: UIColor.white,
          importance: NotificationImportance.High
        )
      ]
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
