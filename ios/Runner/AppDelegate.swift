import Darwin
import Flutter
import GoogleMaps
import UIKit

// Crashes here are native (Swift/Obj-C), so Dart's FlutterError.onError /
// runZonedGuarded never see them -- Flutter just reports "Lost connection to
// device". These handlers print the actual reason to the device log (visible
// in `flutter run`'s terminal output or Xcode's console) before the process
// dies, instead of leaving nothing to go on.
private func adimoveUncaughtExceptionHandler(_ exception: NSException) {
  NSLog(
    "\u{1F534} [fatal] Uncaught exception: %@ - %@",
    exception.name.rawValue, exception.reason ?? "no reason"
  )
  NSLog("\u{1F534} [fatal] Stack trace:\n%@", exception.callStackSymbols.joined(separator: "\n"))
}

private func adimoveSignalHandler(_ signalValue: Int32) {
  NSLog("\u{1F534} [fatal] Crashed with signal %d", signalValue)
  exit(signalValue)
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Read once at launch, then handed to Dart over the config channel below so
  // BusRouteMap can skip creating a GoogleMap view entirely when this is
  // false -- avoiding the native crash instead of just logging it.
  private var mapsApiKeyConfigured = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSSetUncaughtExceptionHandler(adimoveUncaughtExceptionHandler)
    for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE] {
      signal(sig, adimoveSignalHandler)
    }

    // Without this the GoogleMap widget (Track/Map tabs) crashes on iOS the
    // instant it's created -- Android tolerates a missing key with a
    // watermarked map, iOS does not. Key comes from ios/Flutter/ApiKeys.xcconfig
    // via the GMSApiKey entry in Info.plist, mirroring android/local.properties.
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
      !apiKey.isEmpty
    {
      GMSServices.provideAPIKey(apiKey)
      mapsApiKeyConfigured = true
      NSLog("[maps] Google Maps SDK initialised")
    } else {
      NSLog(
        "[maps] GOOGLE_MAPS_API_KEY not set in ios/Flutter/ApiKeys.xcconfig -- "
          + "map tabs will show a placeholder instead of the live map"
      )
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.adimove.app/config",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "hasMapsApiKey":
        result(self?.mapsApiKeyConfigured ?? false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
