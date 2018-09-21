import Foundation
import UIKit
import CoreMotion
import AVFoundation

// 画面回転ロックを掛けると UIDeviceOrientationDidChange の Notification が飛んでこない。
// AVCaptureVideoOrientation を放り込むために必要だったので、自前で CMMotionManager の
// deviceMotion の gravity から計算するやつを書いた。
// 簡単に閾値ベースの実装をした。しかし、出力を比べてみると実際の UIDeviceOrientationDidChange はもうちょっと複雑に積分などをしている様子。

public protocol OrientationDetectorInterface: class {

    // Singleton Pattern
    static var shared: OrientationDetector { get }

    // Result Values
    var orientation: UIDeviceOrientation { get }
    var captureVideoOrientation: AVCaptureVideoOrientation { get }

    // Configure Motion Sensor
    var sensorInterval: TimeInterval { get set } // default 0.1, 10 Hz

    // Start and Stop Motion Sensor
    func startSensor()
    func stopSensor()

}

extension Notification.Name {
    public static let OrientationDetectorOrientationDidChange = Notification.Name("OrientationDetectorOrientationDidChange")
    public static let OrientationDetectorCaptureVideoOrientationDidChange = Notification.Name("OrientationDetectorCaptureVideoOrientationDidChange")
}
