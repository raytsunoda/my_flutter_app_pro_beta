import UIKit
import Flutter
import awesome_notifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Objective-C 版 GeneratedPluginRegistrant を呼ぶ
    GeneratedPluginRegistrant.register(with: self)

    // Awesome Notifications 初期化
    AwesomeNotifications.initialize(
      nil,
      []
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
