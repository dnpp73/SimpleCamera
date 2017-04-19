import Foundation
import UIKit
import CoreMotion
import AVFoundation

public final class OrientationDetector: OrientationDetectorInterface {
    
    public static let OrientationDidChange = NSNotification.Name(rawValue: "OrientationDidChange")
    public static let CaptureVideoOrientationDidChange = NSNotification.Name(rawValue: "CaptureVideoOrientationDidChange")
    
    public static let shared = OrientationDetector() // Singleton
    private init() {}
    
    deinit {
        stopSensor()
    }
    
    private var orientationDidChange: Bool = false
    
    private(set) public var orientation: UIDeviceOrientation = .unknown {
        willSet {
            orientationDidChange = (orientation != newValue)
        }
        didSet {
            if let c = AVCaptureVideoOrientation(deviceOrientation: orientation) {
                captureVideoOrientation = c
            }
            if orientationDidChange {
                NotificationCenter.default.post(name: OrientationDetector.OrientationDidChange, object: nil)
            }
        }
    }
    
    private var captureVideoOrientationDidChange: Bool = false
    
    private(set) public var captureVideoOrientation: AVCaptureVideoOrientation = .portrait {
        willSet {
            captureVideoOrientationDidChange = (captureVideoOrientation != newValue)
        }
        didSet {
            if captureVideoOrientationDidChange {
                NotificationCenter.default.post(name: OrientationDetector.CaptureVideoOrientationDidChange, object: nil)
            }
        }
    }
    
    public var sensorInterval: TimeInterval = 0.1 /* 10 Hz */ {
        didSet {
            if motionManager.isDeviceMotionAvailable && motionManager.isDeviceMotionActive {
                motionManager.deviceMotionUpdateInterval = sensorInterval
            }
        }
    }
    
    private let motionManager = CMMotionManager()
    
    public func startSensor() {
        if motionManager.isDeviceMotionAvailable && !motionManager.isDeviceMotionActive {
            motionManager.deviceMotionUpdateInterval = sensorInterval
            motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { [unowned self] deviceMotion, error in
                guard let deviceMotion = deviceMotion else {
                    return
                }
                
                let thresholdFaceUpDown = 0.3
                let thresholdPortraitLandscape = 0.1
                
                let x = deviceMotion.gravity.x
                let y = deviceMotion.gravity.y
                let z = deviceMotion.gravity.z
                
                if abs(z) > abs(x) + abs(y) + thresholdFaceUpDown {
                    if z > 0 {
                        self.orientation = .faceDown
                    }
                    else {
                        self.orientation = .faceUp
                    }
                }
                else if abs(x) > abs(y) + abs(z) + thresholdPortraitLandscape {
                    if x > 0 {
                        self.orientation = .landscapeRight
                    }
                    else {
                        self.orientation = .landscapeLeft
                    }
                }
                else if abs(y) > abs(x) + abs(z) + thresholdPortraitLandscape {
                    if y > 0 {
                        self.orientation = .portraitUpsideDown
                    }
                    else {
                        self.orientation = .portrait
                    }
                }
                else {
                    // 閾値未満
                }
            }
        }
    }
    
    public func stopSensor() {
        if motionManager.isDeviceMotionAvailable && motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        orientation = .unknown
    }
    
}
