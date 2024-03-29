#if canImport(UIKit)

import Foundation
import UIKit
import AVFoundation

@objc public protocol SimpleCameraObservable: AnyObject {
    func simpleCameraDidStartRunning(simpleCamera: SimpleCamera)
    func simpleCameraDidStopRunning(simpleCamera: SimpleCamera)

    func simpleCameraDidChangeZoomFactor(simpleCamera: SimpleCamera)

    func simpleCameraDidChangeFocusPointOfInterest(simpleCamera: SimpleCamera)
    func simpleCameraDidChangeExposurePointOfInterest(simpleCamera: SimpleCamera)
    func simpleCameraDidResetFocusAndExposure(simpleCamera: SimpleCamera)

    func simpleCameraDidSwitchCameraInput(simpleCamera: SimpleCamera)

    #warning("TODO")
//    func simpleCameraSessionRuntimeError(simpleCamera: SimpleCamera, error: AVError)
//    @available(iOS 9.0, *) func simpleCameraSessionWasInterrupted(simpleCamera: SimpleCamera, reason: AVCaptureSession.InterruptionReason)
    func simpleCameraSessionInterruptionEnded(simpleCamera: SimpleCamera)
}

@objc public protocol SimpleCameraVideoDataOutputObservable: AnyObject {
    func simpleCameraVideoDataOutputObserve(captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    func simpleCameraVideoDataOutputObserve(captureOutput: AVCaptureOutput, didDrop   sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
}

@objc public protocol SimpleCameraAudioDataOutputObservable: AnyObject {
    func simpleCameraAudioDataOutputObserve(captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
}

public enum CameraMode {
    case unknown
    case photo
    case movie
}

public protocol SimpleCameraInterface: AnyObject {

    // Singleton Pattern
    static var shared: SimpleCamera { get }

    // AVCaptureVideoPreviewView Setting
    func setSession(to captureVideoPreviewView: AVCaptureVideoPreviewView)

    // Camera Session Control
    var isRunning: Bool { get }
    func startRunning()
    func stopRunning()

    // set Photo or Movie preferred preset. may change fov
    var mode: CameraMode { get }
    func setPhotoMode()
    func setMovieMode()

    // Capture Image
    var isCapturingImage: Bool { get }
    var captureLimitSize: CGSize { get set } // CGSize.zero is limitless
    func capturePhotoImageAsynchronously(completion: @escaping (_ image: UIImage?, _ metadata: [String: Any]?) -> Void)
    func captureSilentImageAsynchronously(completion: @escaping (_ image: UIImage?, _ metadata: [String: Any]?) -> Void)

    // Record Movie
    var isEnabledAudioRecording: Bool { get set } // Default false. need `NSMicrophoneUsageDescription` key in Info.plist
    var isRecordingMovie: Bool { get }
    func startRecordMovie(to url: URL) -> Bool // return recoding start success or fail. @discardableResult
    func stopRecordMovie()

    // Zoom
    var zoomFactor: CGFloat { get set }
    var zoomFactorLimit: CGFloat { get set } // Default 6.0
    var maxZoomFactor: CGFloat { get } // Device Depends

    // Focus, Exposure
    var focusPointOfInterest: CGPoint { get }
    func focus(at devicePoint: CGPoint, focusMode: AVCaptureDevice.FocusMode, monitorSubjectAreaChange: Bool)

    var exposurePointOfInterest: CGPoint { get }
    func exposure(at devicePoint: CGPoint, exposureMode: AVCaptureDevice.ExposureMode, monitorSubjectAreaChange: Bool)

    func focusAndExposure(at devicePoint: CGPoint, focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, monitorSubjectAreaChange: Bool)
    func resetFocusAndExposure()

    // Front or Back
    var isCurrentInputFront: Bool { get }
    var isCurrentInputBack: Bool { get }
    func switchCameraInputToFront()
    func switchCameraInputToBack()
    func switchCameraInput()

    // Orientation, Mirrored Setting
    var isMirroredImageIfFrontCamera: Bool { get set } // Default false
    var isFollowDeviceOrientationWhenCapture: Bool { get set } // Default true

    // Manage SimpleCamera Observers
    func add(simpleCameraObserver: SimpleCameraObservable)
    func remove(simpleCameraObserver: SimpleCameraObservable)

    // Manage VideoDataOutput Observers
    func add(videoDataOutputObserver: SimpleCameraVideoDataOutputObservable)
    func remove(videoDataOutputObserver: SimpleCameraVideoDataOutputObservable)

    // Manage AudioOutput Observers
    func add(audioDataOutputObserver: SimpleCameraAudioDataOutputObservable)
    func remove(audioDataOutputObserver: SimpleCameraAudioDataOutputObservable)

    // Utility
    var preferredUIImageOrientationForVideoDataOutput: UIImage.Orientation { get }
}

#endif
