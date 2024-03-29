#if canImport(UIKit)

import Foundation
import UIKit
import AVFoundation

// struct にしたいけど deinit が使えないのと、
// AVCaptureVideoDataOutputSampleBufferDelegate が class 指定というか NSObject 指定なのでしょうがない。
public final class SimpleCamera: NSObject, SimpleCameraInterface {

    public static let shared = SimpleCamera() // Singleton
    override private init() {}

    fileprivate let sessionQueue = DispatchQueue(label: "org.dnpp.SimpleCamera.sessionQueue") // attributes: .concurrent しなければ serial queue
    private let videoDataOutputQueue = DispatchQueue(label: "org.dnpp.SimpleCamera.VideoDataOutput.delegateQueue")

    fileprivate let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    fileprivate let videoDataOutput = AVCaptureVideoDataOutput() // extension の AVCaptureVideoDataOutputSampleBufferDelegate 内で使っているため fileprivate
    fileprivate let audioDataOutput = AVCaptureAudioDataOutput() // extension の AVCaptureVideoDataOutputSampleBufferDelegate 内で使っているため fileprivate
    fileprivate let movieFileOutput = AVCaptureMovieFileOutput()

    private var frontCameraVideoInput: AVCaptureDeviceInput?
    private var backCameraVideoInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?

    fileprivate var isPhotoCapturingImage: Bool = false
    fileprivate var isSilentCapturingImage: Bool = false
    fileprivate var photoCaptureImageCompletion: ((_ image: UIImage?, _ metadata: [String: Any]?) -> Void)? // extension で使っているため fileprivate
    fileprivate var silentCaptureImageCompletion: ((_ image: UIImage?, _ metadata: [String: Any]?) -> Void)? // extension の AVCaptureVideoDataOutputSampleBufferDelegate 内で使っているため fileprivate

    private let observers: NSHashTable<SimpleCameraObservable> = NSHashTable.weakObjects()
    fileprivate let videoDataOutputObservers: NSHashTable<SimpleCameraVideoDataOutputObservable> = NSHashTable.weakObjects()
    fileprivate let audioDataOutputObservers: NSHashTable<SimpleCameraAudioDataOutputObservable> = NSHashTable.weakObjects()

    private weak var captureVideoPreviewView: AVCaptureVideoPreviewView?

    // MARK: - Initializer

    deinit { // deinit は class だけだよ
        tearDown()
    }

    // MARK: - Public Functions

    public func setSession(to captureVideoPreviewView: AVCaptureVideoPreviewView) {
        if let c = self.captureVideoPreviewView, c.session != nil {
            c.session = nil
        }
        // sessionQueue.async { } で囲ってしまうとメインスレッド外から UI を触ってしまうので外す。
        captureVideoPreviewView.session = captureSession
        self.captureVideoPreviewView = captureVideoPreviewView
    }

    public var isRunning: Bool {
        guard isConfigured else {
            return false
        }
        return captureSession.isRunning
    }

    public func startRunning() {
        DispatchQueue.global().async {
            self.configure() // この実行でカメラの許可ダイアログが出る
            guard self.isConfigured else {
                return
            }
            if !self.isRunning {
                DispatchQueue.main.async {
                    OrientationDetector.shared.startSensor()
                }
                self.sessionQueue.async {
                    self.captureSession.startRunning()
                    self.resetZoomFactor(sync: false) // true にしたり zoomFactor の setter に入れるとデッドロックするので注意
                    self.resetFocusAndExposure()
                }
            }
        }
    }

    public func stopRunning() {
        guard isConfigured else {
            return
        }
        if isRunning {
            sessionQueue.async {
                self.captureSession.stopRunning()
            }
            OrientationDetector.shared.stopSensor()
        }
    }

    // MARK: Preset

    public private(set) var mode: CameraMode = .unknown

    public func setPhotoMode() {
        sessionQueue.sync {
            guard isRecordingMovie == false else {
                return
            }
            guard mode != .photo else {
                return
            }

            captureSession.beginConfiguration() // defer より前の段階で commit したい

            captureSession.removeOutput(movieFileOutput)
            if let audioDeviceInput = audioDeviceInput {
                captureSession.removeInput(audioDeviceInput)
            }

            if captureSession.canSetSessionPreset(.photo) {
                captureSession.canSetSessionPreset(.photo)
            }

            if let frontCameraDevice = frontCameraVideoInput?.device {
                if let f = frontCameraDevice.formats.fliter420v.filterAspect4_3.sortedByQuality.first {
                    frontCameraDevice.lockAndConfiguration {
                        frontCameraDevice.activeFormat = f
                    }
                }
            }

            if let backCameraDevice = backCameraVideoInput?.device {
                if let f = backCameraDevice.formats.fliter420v.filterAspect4_3.sortedByQuality.first {
                    backCameraDevice.lockAndConfiguration {
                        backCameraDevice.activeFormat = f
                    }
                }
            }

            captureSession.commitConfiguration()

            mode = .photo

            resetZoomFactor(sync: false) // true にしたり zoomFactor の setter に入れるとデッドロックするので注意
            resetFocusAndExposure()
        }
    }

    public func setMovieMode() {
        sessionQueue.sync {
            guard isRecordingMovie == false else {
                return
            }
            guard mode != .movie else {
                return
            }

            captureSession.beginConfiguration() // defer より前の段階で commit したい

            // 最初は configure() 内で作っていたんだけど、そうするとマイクの許可画面とかが出てきて
            // マイク使わない、動画無しの場合のアプリみたいなの作るときに不便そうだったのでこっちにした。
            if isEnabledAudioRecording {
                if audioDeviceInput == nil {
                    do {
                        if let audioDevice = AVCaptureDevice.default(for: .audio) {
                            // ここで AVCaptureDeviceInput を作ると、その時は落ちないんだけど、その先の適当なタイミングで落ちる。
                            // マイクの許可が必要。 iOS 10 以降では plist に書かないとダメだよ。
                            audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
                        } else {
                            audioDeviceInput = nil
                        }
                    } catch let error /* as NSError */ {
                        print(error)
                        audioDeviceInput = nil
                    }
                }

                if let audioDeviceInput = audioDeviceInput, captureSession.canAddInput(audioDeviceInput) {
                    captureSession.addInput(audioDeviceInput)
                }
            }

            /*
            // ここで movieFileOutput を addOutput してしまうと videoDataOutput に何も流れてこなくなるのでダメ。
            // 一瞬暗くなるけど録画直前に addOutput するしかなさそう。
            if captureSession.canAddOutput(movieFileOutput) {
                captureSession.addOutput(movieFileOutput)
            }
             */

            if captureSession.canSetSessionPreset(.high) {
                captureSession.canSetSessionPreset(.high)
            }

            if let frontCameraDevice = frontCameraVideoInput?.device {
                if let f = frontCameraDevice.formats.fliter420v.filterAspect16_9.sortedByQuality.first {
                    frontCameraDevice.lockAndConfiguration {
                        frontCameraDevice.activeFormat = f
                    }
                }
            }

            if let backCameraDevice = backCameraVideoInput?.device {
                if let f = backCameraDevice.formats.fliter420v.filterAspect16_9.sortedByQuality.first {
                    backCameraDevice.lockAndConfiguration {
                        backCameraDevice.activeFormat = f
                    }
                }
            }

            captureSession.commitConfiguration()

            mode = .movie

            resetZoomFactor(sync: false) // true にしたり zoomFactor の setter に入れるとデッドロックするので注意
            resetFocusAndExposure()
        }
    }

    // MARK: Capture Image

    public var isCapturingImage: Bool {
        isSilentCapturingImage || isPhotoCapturingImage
    }

    public var captureLimitSize: CGSize = .zero

    public func capturePhotoImageAsynchronously(completion: @escaping (_ image: UIImage?, _ metadata: [String: Any]?) -> Void) {
        guard isConfigured else {
            completion(nil, nil)
            return
        }
        guard isRecordingMovie == false else {
            completion(nil, nil)
            return
        }
        guard captureSession.isRunning else {
            completion(nil, nil)
            return
        }
        if isPhotoCapturingImage {
            completion(nil, nil)
            return
        }

        if isSilentCapturingImage {
            // 連打などで前のやつが処理中な場合
            completion(nil, nil)
            return
        }

        let settings = AVCapturePhotoSettings()
        // settings.flashMode = .auto
        // settings.isHighResolutionPhotoEnabled = false

        isPhotoCapturingImage = true
        photoCaptureImageCompletion = completion

        /*
        // AVCaptureStillImageOutput の captureStillImageAsynchronously であれば撮影直前に connection の videoOrientation を弄っても問題なかったが
        // AVCapturePhotoOutput ではどうやら弄っても効かない模様。
        let videoOrientation: AVCaptureVideoOrientation
        if self.isFollowDeviceOrientationWhenCapture {
            videoOrientation = OrientationDetector.shared.captureVideoOrientation
        } else {
            videoOrientation = .portrait
        }
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: AVMediaType.video) {
                if photoOutputConnection.isVideoOrientationSupported {
                    self.captureSession.beginConfiguration()
                    photoOutputConnection.videoOrientation = videoOrientation
                    self.captureSession.commitConfiguration() // defer より前のタイミングで commit したい
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
         */
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @available(*, deprecated, renamed: "capturePhotoImageAsynchronously")
    public func captureStillImageAsynchronously(completion: @escaping (_ image: UIImage?, _ metadata: [String: Any]?) -> Void) {
        capturePhotoImageAsynchronously(completion: completion)
    }
    /*
    public func captureStillImageAsynchronously(completion: @escaping (_ image: UIImage?, _ metadata: [String: Any]?) -> Void) {
        guard isConfigured else {
            completion(nil, nil)
            return
        }
        guard isRecordingMovie == false else {
            completion(nil, nil)
            return
        }
        guard captureSession.isRunning else {
            completion(nil, nil)
            return
        }
        guard stillImageOutput.isCapturingStillImage == false else {
            completion(nil, nil)
            return
        }

        let videoOrientation: AVCaptureVideoOrientation
        if self.isFollowDeviceOrientationWhenCapture {
            videoOrientation = OrientationDetector.shared.captureVideoOrientation
        } else {
            videoOrientation = .portrait
        }

        sessionQueue.async {
            let stillImageOutputCaptureConnection: AVCaptureConnection = self.stillImageOutput.connection(with: .video)! // swiftlint:disable:this force_unwrapping
            // captureStillImageAsynchronously であれば撮影直前に connection の videoOrientation を弄っても問題なさそう
            self.captureSession.beginConfiguration()
            stillImageOutputCaptureConnection.videoOrientation = videoOrientation
            self.captureSession.commitConfiguration() // defer より前のタイミングで commit したい

            self.stillImageOutput.captureStillImageAsynchronously(from: stillImageOutputCaptureConnection) { (imageDataBuffer, error) -> Void in
                guard let imageDataBuffer = imageDataBuffer, let data = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataBuffer) else {
                    onMainThreadAsync {
                        completion(nil, nil)
                    }
                    return
                }
                guard let rawImage = UIImage(data: data) else {
                    onMainThreadAsync {
                        completion(nil, nil)
                    }
                    return
                }

                let scaledImage: UIImage
                if self.captureLimitSize == .zero {
                    scaledImage = rawImage
                } else {
                    guard let c = CIImage(image: rawImage), let i = createUIImage(from: c, limitSize: self.captureLimitSize, imageOrientation: rawImage.imageOrientation) else {
                        onMainThreadAsync {
                            completion(nil, nil)
                        }
                        return
                    }
                    scaledImage = i
                }

                let metadata = CMCopyDictionaryOfAttachments(allocator: nil, target: imageDataBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any]
                let mirrored = self.isMirroredImageIfFrontCamera && stillImageOutputCaptureConnection.isFrontCameraDevice
                let image = mirrored ? scaledImage.mirrored : scaledImage
                onMainThreadAsync {
                    completion(image, metadata)
                }
            }
        }

    }
     */

    public func captureSilentImageAsynchronously(completion: @escaping (_ image: UIImage?, _ metadata: [String: Any]?) -> Void) {
        guard isConfigured else {
            completion(nil, nil)
            return
        }
        guard isRecordingMovie == false else {
            completion(nil, nil)
            return
        }
        guard captureSession.isRunning else {
            completion(nil, nil)
            return
        }

        if isSilentCapturingImage {
            // 連打などで前のやつが処理中な場合
            completion(nil, nil)
            return
        }

        // Block を保持しておいて、次に AVCaptureVideoDataOutputSampleBufferDelegate で呼ばれた時に UIImage 作って返す。
        isSilentCapturingImage = true
        videoDataOutputQueue.sync {
            silentCaptureImageCompletion = completion
        }
    }

    // MARK: - Record Movie

    public var isEnabledAudioRecording: Bool = false

    public fileprivate(set) var isRecordingMovie: Bool = false

    @discardableResult
    public func startRecordMovie(to url: URL) -> Bool {
        guard isRecordingMovie == false else {
            return false
        }
        guard mode == .movie else {
            return false
        }
        guard url.isFileURL else {
            return false
        }
        guard captureSession.canAddOutput(movieFileOutput) else {
            return false
        }
        sessionQueue.sync {
            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
            }
            // movieFileOutput を使うと自動で videoDataOutput と audioDataOutput へのデータの流れが止まるのでこうなってる。
            captureSession.removeOutput(videoDataOutput)
            captureSession.removeOutput(audioDataOutput)
            captureSession.addOutput(movieFileOutput)
            let videoOrientation: AVCaptureVideoOrientation
            if self.isFollowDeviceOrientationWhenCapture {
                videoOrientation = OrientationDetector.shared.captureVideoOrientation
            } else {
                videoOrientation = .portrait
            }
            movieFileOutput.connection(with: .video)?.videoOrientation = videoOrientation
        }

        isRecordingMovie = true
        // videoDataOutput, audioDataOutput, movieFileOutput を captureSession に足したり消したりしてる関係で、デバイスの初期化が走ってしまい少し暗くなるので気持ちの待ちを入れる。
        sessionQueue.asyncAfter(deadline: .now() + 0.3) {
            self.movieFileOutput.startRecording(to: url, recordingDelegate: self)
        }
        return true
    }

    public func stopRecordMovie() {
        sessionQueue.async {
            self.movieFileOutput.stopRecording()
        }
    }

    // MARK: Camera Setting

    #warning("ズームだけ実装した。ホワイトバランスや ISO やシャッタースピードの調整は後で lockCurrentCameraDeviceAndConfigure を使って作る。")

    private var currentInput: AVCaptureDeviceInput? {
        guard isConfigured else {
            return nil
        }
        // input は 1 つだけという前提（現状の iOS では全部そうなので）
        return captureSession.inputs.first as? AVCaptureDeviceInput
    }

    internal var currentDevice: AVCaptureDevice? {
        guard isConfigured else {
            return nil
        }
        return currentInput?.device
    }

    private func lockCurrentCameraDeviceAndConfigure(sync: Bool = true, configurationBlock: @escaping () -> Void) {
        guard isConfigured else {
            return
        }
        currentDevice?.lockAndConfiguration(queue: sessionQueue, sync: sync, configurationBlock: configurationBlock)
    }

    // MARK: Zoom

    public var zoomFactor: CGFloat {
        get {
            guard let device = currentDevice else {
                return 1.0
            }
            if isCurrentInputBack && hasUltraWideCameraInBackCamera {
                return device.videoZoomFactor / 2.0
            } else {
                return device.videoZoomFactor
            }
        }
        set {
            lockCurrentCameraDeviceAndConfigure {
                guard let lockedDevice = self.currentDevice else {
                    return
                }
                let minZoomFactor = self.minZoomFactor
                let maxZoomFactor = self.maxZoomFactor
                let validatedZoomFactor = min(max(newValue, minZoomFactor), maxZoomFactor)
                if self.isCurrentInputBack && self.hasUltraWideCameraInBackCamera {
                    lockedDevice.videoZoomFactor = validatedZoomFactor * 2.0
                } else {
                    lockedDevice.videoZoomFactor = validatedZoomFactor
                }
            }
        }
    }

    private func resetZoomFactor(sync: Bool) {
        lockCurrentCameraDeviceAndConfigure(sync: sync) {
            guard let lockedDevice = self.currentDevice else {
                return
            }
            if self.isCurrentInputBack && self.hasUltraWideCameraInBackCamera {
                lockedDevice.videoZoomFactor = 2.0
            } else {
                lockedDevice.videoZoomFactor = 1.0
            }
        }
    }

    public var zoomFactorLimit: CGFloat = 6.0 {
        didSet {
            if zoomFactor > zoomFactorLimit {
                zoomFactor = zoomFactorLimit
            }
        }
    }

    public var maxZoomFactor: CGFloat {
        guard let videoMaxZoomFactor = currentDevice?.activeFormat.videoMaxZoomFactor else {
            return 1.0
        }
        return min(zoomFactorLimit, videoMaxZoomFactor)
    }

    public var minZoomFactor: CGFloat {
        if isCurrentInputBack && hasUltraWideCameraInBackCamera {
            return 0.5
        } else {
            return 1.0
        }
    }

    // MARK: Focus, Exposure

    public var focusPointOfInterest: CGPoint {
        guard let device = currentDevice else {
            return CGPoint.zero
        }
        return device.focusPointOfInterest
    }

    public func focus(at devicePoint: CGPoint, focusMode: AVCaptureDevice.FocusMode, monitorSubjectAreaChange: Bool) {
        lockCurrentCameraDeviceAndConfigure(sync: false) {
            guard let device = self.currentDevice else {
                return
            }
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = focusMode
            }
            device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
        }
    }

    public var exposurePointOfInterest: CGPoint {
        guard let device = currentDevice else {
            return CGPoint.zero
        }
        return device.exposurePointOfInterest
    }

    public func exposure(at devicePoint: CGPoint, exposureMode: AVCaptureDevice.ExposureMode, monitorSubjectAreaChange: Bool) {
        lockCurrentCameraDeviceAndConfigure(sync: false) {
            guard let device = self.currentDevice else {
                return
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = exposureMode
            }
            device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
        }
    }

    public func focusAndExposure(at devicePoint: CGPoint, focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, monitorSubjectAreaChange: Bool) {
        lockCurrentCameraDeviceAndConfigure(sync: false) {
            guard let device = self.currentDevice else {
                return
            }
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = focusMode
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = exposureMode
            }
            device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
        }
    }

    public func resetFocusAndExposure() {
        guard let device = self.currentDevice else {
            return
        }
        lockCurrentCameraDeviceAndConfigure(sync: false) {
            let center = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported {
                let focusMode: AVCaptureDevice.FocusMode
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    focusMode = .continuousAutoFocus
                } else {
                    focusMode = .autoFocus
                }
                device.focusPointOfInterest = center
                device.focusMode = focusMode
            }
            if device.isExposurePointOfInterestSupported {
                let exposureMode: AVCaptureDevice.ExposureMode
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    exposureMode = .continuousAutoExposure
                } else {
                    exposureMode = .autoExpose
                }
                device.exposurePointOfInterest = center
                device.exposureMode = exposureMode
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            onMainThreadAsync {
                for observer in self.observers.allObjects {
                    observer.simpleCameraDidResetFocusAndExposure(simpleCamera: self)
                }
            }
        }
    }

    // MARK: Switch Camera Input Front/Back

    private func switchCaptureDeviceInput(_ captureDeviceInput: AVCaptureDeviceInput) {
        guard isConfigured else {
            return
        }
        guard let currentInput = currentInput else {
            return
        }
        guard !isRecordingMovie else {
            // 動画記録中も切り替えられることは切り替えられるけど、iOS 側は記録の方が中断される感じの優先度になってる。
            return
        }

        var switchSucceed: Bool = false

        sessionQueue.sync {
            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
            }
            captureSession.removeInput(currentInput)
            if captureSession.canAddInput(captureDeviceInput) {
                captureSession.addInput(captureDeviceInput)
                switchSucceed = true
            } else if captureSession.canAddInput(currentInput) {
                captureSession.addInput(currentInput)
            }

            // let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: UIApplication.shared.statusBarOrientation) ?? .portrait
            // とりあえず portrait に戻す
            let videoOrientation = AVCaptureVideoOrientation.portrait
            videoDataOutput.connection(with: .video)?.videoOrientation = videoOrientation
        }

        if switchSucceed {
            // 内部で sessionQueue.async してるので外に出しておきたい
            onMainThreadAsync {
                for observer in self.observers.allObjects {
                    observer.simpleCameraDidSwitchCameraInput(simpleCamera: self)
                }
            }
            resetZoomFactor(sync: true)
            resetFocusAndExposure()
        }
    }

    public var isCurrentInputFront: Bool {
        guard let device = currentDevice else {
            return false
        }
        return device.position == .front
    }

    public func switchCameraInputToFront() {
        guard let device = currentDevice, let frontCameraVideoInput = frontCameraVideoInput else {
            return
        }
        if device.position != .front {
            switchCaptureDeviceInput(frontCameraVideoInput)
        }
    }

    public var isCurrentInputBack: Bool {
        guard let device = currentDevice else {
            return false
        }
        return device.position == .back
    }

    public func switchCameraInputToBack() {
        guard let device = currentDevice, let backCameraVideoInput = backCameraVideoInput else {
            return
        }
        if device.position != .back {
            switchCaptureDeviceInput(backCameraVideoInput)
        }
    }

    public func switchCameraInput() {
        if isCurrentInputFront {
            switchCameraInputToBack()
        } else if isCurrentInputBack {
            switchCameraInputToFront()
        }
    }

    // MARK: Orientation, Mirrored Setting

    public var isMirroredImageIfFrontCamera = false
    public var isFollowDeviceOrientationWhenCapture = true

    // MARK: Manage SimpleCamera Observers

    public func add(simpleCameraObserver: SimpleCameraObservable) {
        if !observers.contains(simpleCameraObserver) {
            observers.add(simpleCameraObserver)
        }
    }

    public func remove(simpleCameraObserver: SimpleCameraObservable) {
        if observers.contains(simpleCameraObserver) {
            observers.remove(simpleCameraObserver)
        }
    }

    // MARK: Manage VideoDataOutput Observer

    public func add(videoDataOutputObserver: SimpleCameraVideoDataOutputObservable) {
        if !videoDataOutputObservers.contains(videoDataOutputObserver) {
            videoDataOutputObservers.add(videoDataOutputObserver)
        }
    }

    public func remove(videoDataOutputObserver: SimpleCameraVideoDataOutputObservable) {
        if videoDataOutputObservers.contains(videoDataOutputObserver) {
            videoDataOutputObservers.remove(videoDataOutputObserver)
        }
    }

    // MARK: Manage AudioDataOutput Observers

    public func add(audioDataOutputObserver: SimpleCameraAudioDataOutputObservable) {
        if !audioDataOutputObservers.contains(audioDataOutputObserver) {
            audioDataOutputObservers.add(audioDataOutputObserver)
        }

    }

    public func remove(audioDataOutputObserver: SimpleCameraAudioDataOutputObservable) {
        if audioDataOutputObservers.contains(audioDataOutputObserver) {
            audioDataOutputObservers.remove(audioDataOutputObserver)
        }
    }

    // MARK: - Private Functions

    private var hasUltraWideCameraInBackCamera = false // configure（） 内で backCameraVideoInput を探すときに決める。

    private var isConfigured: Bool = false

    private func configure() { // この configure 実行でカメラの許可ダイアログが出る
        if isConfigured || (TARGET_OS_SIMULATOR != 0) {
            return
        }
        defer {
            isConfigured = true
        }

        sessionQueue.sync {
            // CaptureDeviceInput の準備
            // iOS 8 以降に限定しているのでバックカメラとフロントカメラは大体全ての機種にあるけど、
            // 唯一 iPod Touch 5th Generation にのみバックカメラが無いモデルがある。
            do {
                // iOS 8,9 のカメラアクセス許可ダイアログはここで出る。
                // iOS 10 では info.plist の NSCameraUsageDescription に許可の文言を書かないとアプリごと abort() してしまう。
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                    frontCameraVideoInput = try AVCaptureDeviceInput(device: device)
                } else {
                    print("[SimpleCamera.configure()] frontCameraVideoInput is nil")
                    frontCameraVideoInput = nil
                }
            } catch let error {
                print(error)
                print("[SimpleCamera.configure()] frontCameraVideoInput is nil")
                frontCameraVideoInput = nil
            }
            do {
                let device: AVCaptureDevice?
                // 汎用カメラライブラリを目指して作っているので、デバイスの優先順位の決め方は
                // - 用途を絞った 1 枚のカメラ (広角・望遠・超広角) は使わない
                // - 複数カメラを一気に扱えるカメラを指定する
                // - カメラの数が多い方を優先する
                // という感じでやっていく。
                if #available(iOS 13.0, *) {
                    if let tripleCameraDevice = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                        hasUltraWideCameraInBackCamera = true
                        device = tripleCameraDevice
                    } else if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                        device = dualCameraDevice
                    } else if let dualWideCameraDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                        hasUltraWideCameraInBackCamera = true
                        device = dualWideCameraDevice
                    } else if let wideAngleCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                        device = wideAngleCameraDevice
                    } else {
                        device = nil
                    }
                } else {
                    if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                        device = dualCameraDevice
                    } else if let wideAngleCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                        device = wideAngleCameraDevice
                    } else {
                        device = nil
                    }
                }
                if let device = device {
                    backCameraVideoInput = try AVCaptureDeviceInput(device: device)
                } else {
                    print("[SimpleCamera.configure()] backCameraVideoInput is nil")
                    backCameraVideoInput = nil
                }
            } catch let error {
                print(error)
                print("[SimpleCamera.configure()] backCameraVideoInput is nil")
                backCameraVideoInput = nil
            }

            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
            }

            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                photoOutput.isLivePhotoCaptureEnabled = false
            }

            // videoDataOutput を調整して captureSession に放り込む
            // kCVPixelBufferPixelFormatTypeKey の部分だけど、
            // Available pixel format types on this platform are (
            //     420v, // たぶん kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            //     420f,
            //     BGRA // kCVPixelFormatType_32BGRA
            // ).
            // とのこと。
            // iPhone 4s でのみ再現するんだけど、マジで何も言わずデバッガにも引っ掛からずにアプリが落ちるので
            // cameraVideoInputDevice と videoDataOutput のフォーマットを 420v の統一してみたところ落ちなくなった。
            videoDataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange as UInt32)]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            if captureSession.canAddOutput(videoDataOutput) {
                captureSession.addOutput(videoDataOutput)
            }

            audioDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            if captureSession.canAddOutput(audioDataOutput) {
                captureSession.addOutput(audioDataOutput)
            }

            // backCamera を captureSession に放り込む
            if let backCameraVideoInput = backCameraVideoInput {
                if captureSession.canAddInput(backCameraVideoInput) {
                    captureSession.addInput(backCameraVideoInput)
                }
            }

            // バックカメラだけじゃなくてフロントカメラもセッションに突っ込んでみようとすると
            // Multiple audio/video AVCaptureInputs are not currently supported.
            // と怒られる。
            // バックカメラを caputureSession に放り込めなかった場合にここを通過するので
            // デフォルトではバックカメラ、iPod Touch 5th の一部モデルのみフロントカメラで初期化される。
            if let frontCameraVideoInput = frontCameraVideoInput {
                if captureSession.canAddInput(frontCameraVideoInput) {
                    captureSession.addInput(frontCameraVideoInput)
                }
            }

            // stillImageOutput と videoDataOutput の videoOrientation を InterfaceOrientation に揃えるか縦にしておく。
            // captureSession に addInput した後じゃないと connection は nil なので videoOrientation を取ろうとすると nil アクセスで死にます。
            // デフォルトでは stillImageOutput が 1 (portrait) で videoDataOutput が 3 (landscapeRight)
            // let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: UIApplication.shared.statusBarOrientation) ?? .portrait
            // とりあえず portrait に戻す
            let videoOrientation = AVCaptureVideoOrientation.portrait
            if let photoOutputConnection = photoOutput.connection(with: AVMediaType.video) {
                if photoOutputConnection.isVideoOrientationSupported {
                    photoOutputConnection.videoOrientation = videoOrientation
                }
                photoOutputConnection.videoScaleAndCropFactor = 1.0
            }
            if let videoDataOutputConnection = videoDataOutput.connection(with: AVMediaType.video) {
                if videoDataOutputConnection.isVideoOrientationSupported {
                    videoDataOutputConnection.videoOrientation = videoOrientation
                }
                videoDataOutputConnection.videoScaleAndCropFactor = 1.0
            }
        }

        // captureSession に preset を放り込んだり AVCaptureDevice に format を放り込んだりする。
        // sessionQueue.sync で放り込むと同じ DispatchQueue なのでデッドロックするため外に出す。
        setPhotoMode()

        // NotificationCenter と KVO 周り
        sessionQueue.sync {
            addObservers()
        }
    }

    private func tearDown() {
        if !isConfigured || (TARGET_OS_SIMULATOR != 0) {
            return
        }

        videoDataOutputQueue.sync {
            silentCaptureImageCompletion = nil
            isSilentCapturingImage = false
            isPhotoCapturingImage = false
        }
        sessionQueue.sync {
            removeObservers()

            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            for output in captureSession.outputs.reversed() {
                captureSession.removeOutput(output)
            }
            for input in captureSession.inputs.reversed() {
                captureSession.removeInput(input)
            }
            frontCameraVideoInput = nil
            backCameraVideoInput  = nil
            audioDeviceInput = nil
            isConfigured = false
        }
    }

    // MARK: KVO and Notifications

    private var keyValueObservations: [NSKeyValueObservation] = []

    private var showDebugMessages = false

    private func addObservers() {
        #warning("kaku")
        var observations: [NSKeyValueObservation?] = []
        observations.append(captureSession.observe(\.isRunning, options: .new) { (captureSession, changes) in
            guard let isRunning = changes.newValue else {
                return
            }
            onMainThreadAsync {
                self.isRunningForObserve = isRunning
            }
        })
        observations.append(frontCameraVideoInput?.device.observe(\.isAdjustingFocus, options: .new) { (device, changes) in
            guard let isAdjustingFocus = changes.newValue else {
                return
            }
            if self.showDebugMessages {
                print("[KVO] frontCameraDevice isAdjustingFocus: \(isAdjustingFocus)")
            }
        })
        observations.append(backCameraVideoInput?.device.observe(\.isAdjustingFocus, options: .new) { (device, changes) in
            guard let isAdjustingFocus = changes.newValue else {
                return
            }
            if self.showDebugMessages {
                print("[KVO] backCameraDevice isAdjustingFocus: \(isAdjustingFocus)")
            }
        })
        observations.append(frontCameraVideoInput?.device.observe(\.isAdjustingExposure, options: .new) { (device, changes) in
            guard let isAdjustingExposure = changes.newValue else {
                return
            }
            if self.showDebugMessages {
                print("[KVO] frontCameraDevice isAdjustingExposure: \(isAdjustingExposure)")
            }
        })
        observations.append(backCameraVideoInput?.device.observe(\.isAdjustingExposure, options: .new) { (device, changes) in
            guard let isAdjustingExposure = changes.newValue else {
                return
            }
            if self.showDebugMessages {
                print("[KVO] backCameraDevice isAdjustingExposure: \(isAdjustingExposure)")
            }
        })
        observations.append(frontCameraVideoInput?.device.observe(\.isAdjustingWhiteBalance, options: .new) { (device, changes) in
            guard let isAdjustingWhiteBalance = changes.newValue else {
                return
            }
            if self.showDebugMessages {
                print("[KVO] frontCameraDevice adjustingWhiteBalance: \(isAdjustingWhiteBalance)")
            }
            // 白色点を清く正しく取ってくるの、色々ありそうなのでめんどくさそう。Dash で 'AVCaptureDevice white' くらいまで打てば出てくる英語を読まないといけない。
        })
        observations.append(backCameraVideoInput?.device.observe(\.isAdjustingWhiteBalance, options: .new) { (device, changes) in
            guard let isAdjustingWhiteBalance = changes.newValue else {
                return
            }
            if self.showDebugMessages {
                print("[KVO] backCameraDevice adjustingWhiteBalance: \(isAdjustingWhiteBalance)")
            }
            // 白色点を清く正しく取ってくるの、色々ありそうなのでめんどくさそう。Dash で 'AVCaptureDevice white' くらいまで打てば出てくる英語を読まないといけない。
        })
        observations.append(frontCameraVideoInput?.device.observe(\.focusPointOfInterest, options: .new) { (device, changes) in
            guard let focusPointOfInterest = changes.newValue else {
                return
            }
            onMainThreadAsync {
                self.focusPointOfInterestForObserve = focusPointOfInterest
            }
        })
        observations.append(backCameraVideoInput?.device.observe(\.focusPointOfInterest, options: .new) { (device, changes) in
            guard let focusPointOfInterest = changes.newValue else {
                return
            }
            onMainThreadAsync {
                self.focusPointOfInterestForObserve = focusPointOfInterest
            }
        })
        observations.append(frontCameraVideoInput?.device.observe(\.exposurePointOfInterest, options: .new) { (device, changes) in
            guard let exposurePointOfInterest = changes.newValue else {
                return
            }
            onMainThreadAsync {
                self.exposurePointOfInterestForObserve = exposurePointOfInterest
            }
        })
        observations.append(backCameraVideoInput?.device.observe(\.exposurePointOfInterest, options: .new) { (device, changes) in
            guard let exposurePointOfInterest = changes.newValue else {
                return
            }
            onMainThreadAsync {
                self.exposurePointOfInterestForObserve = exposurePointOfInterest
            }
        })
        observations.append(frontCameraVideoInput?.device.observe(\.videoZoomFactor, options: .new) { (device, changes) in
            guard let videoZoomFactor = changes.newValue else {
                return
            }
            onMainThreadAsync {
                self.zoomFactorForObserve = videoZoomFactor
            }
        })
        observations.append(backCameraVideoInput?.device.observe(\.videoZoomFactor, options: .new) { (device, changes) in
            guard let videoZoomFactor = changes.newValue else {
                return
            }
            onMainThreadAsync {
                if self.hasUltraWideCameraInBackCamera {
                    self.zoomFactorForObserve = videoZoomFactor / 2.0
                } else {
                    self.zoomFactorForObserve = videoZoomFactor
                }
            }
        })
        keyValueObservations = observations.compactMap { $0 }

        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: Notification.Name("AVCaptureDeviceSubjectAreaDidChangeNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: Notification.Name("AVCaptureSessionRuntimeErrorNotification"), object: captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: Notification.Name("AVCaptureSessionWasInterruptedNotification"), object: captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: Notification.Name("AVCaptureSessionInterruptionEndedNotification"), object: captureSession)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        keyValueObservations.removeAll() // NSKeyValueObservation の deinit を発行させるだけで良い。
    }

    @objc
    private func subjectAreaDidChange(notification: Notification) {
        if showDebugMessages {
            print("[Notification] Subject Area Did Change")
        }
        if let device = notification.object as? AVCaptureDevice, device == currentDevice {
            // print("notification.object == currentDevice")
            resetFocusAndExposure()
        }
    }

    @objc
    private func sessionRuntimeError(notification: Notification) {
        #warning("TODO")
        /*
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        let error = AVError(_nsError: errorValue)
        onMainThreadAsync {
            for observer in self.observers.allObjects {
                observer.simpleCameraSessionRuntimeError(simpleCamera: self, error: error)
            }
        }
         */
    }

    @objc
    private func sessionWasInterrupted(notification: Notification) {
        #warning("TODO")
        /*
        guard #available(iOS 9.0, *) else {
            return
        }
        guard let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?, let reasonIntegerValue = userInfoValue.integerValue, let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) else {
            return
        }
        onMainThreadAsync {
            for observer in self.observers.allObjects {
                observer.simpleCameraSessionWasInterrupted(simpleCamera: self, reason: reason)
            }
        }
         */
    }

    @objc
    private func sessionInterruptionEnded(notification: Notification) {
        onMainThreadAsync {
            for observer in self.observers.allObjects {
                observer.simpleCameraSessionInterruptionEnded(simpleCamera: self)
            }
        }
    }

    // MARK: - SimpleCameraObservable

    private var shouldSendIsRunningDidChange: Bool = false
    private var isRunningForObserve: Bool = false {
        willSet {
            shouldSendIsRunningDidChange = (isRunningForObserve != newValue)
        }
        didSet {
            if shouldSendIsRunningDidChange {
                for observer in observers.allObjects {
                    if isRunning {
                        observer.simpleCameraDidStartRunning(simpleCamera: self)
                    } else {
                        observer.simpleCameraDidStopRunning(simpleCamera: self)
                    }
                }
            }
        }
    }

    private var shouldSendZoomFactorDidChange: Bool = false
    private var zoomFactorForObserve: CGFloat = 1.0 {
        willSet {
            shouldSendZoomFactorDidChange = (zoomFactorForObserve != newValue)
        }
        didSet {
            if shouldSendZoomFactorDidChange {
                for observer in observers.allObjects {
                    observer.simpleCameraDidChangeZoomFactor(simpleCamera: self)
                }
            }
        }
    }

    private var shouldSendFocusPointOfInterestDidChange: Bool = false
    private var focusPointOfInterestForObserve: CGPoint = CGPoint(x: 0.5, y: 0.5) {
        willSet {
            shouldSendFocusPointOfInterestDidChange = (focusPointOfInterestForObserve != newValue && newValue != CGPoint(x: 0.5, y: 0.5))
        }
        didSet {
            if shouldSendFocusPointOfInterestDidChange {
                for observer in observers.allObjects {
                    observer.simpleCameraDidChangeFocusPointOfInterest(simpleCamera: self)
                }
            }
        }
    }

    private var shouldSendExposurePointOfInterestDidChange: Bool = false
    private var exposurePointOfInterestForObserve: CGPoint = CGPoint(x: 0.5, y: 0.5) {
        willSet {
            shouldSendExposurePointOfInterestDidChange = (exposurePointOfInterestForObserve != newValue && newValue != CGPoint(x: 0.5, y: 0.5))
        }
        didSet {
            if shouldSendExposurePointOfInterestDidChange {
                for observer in observers.allObjects {
                    observer.simpleCameraDidChangeExposurePointOfInterest(simpleCamera: self)
                }
            }
        }
    }

}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension SimpleCamera: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    public var preferredUIImageOrientationForVideoDataOutput: UIImage.Orientation {
        guard isRunning else {
            return .up
        }

        // 撮影直前に connection の videoOrientation を弄ると実用的に問題があるので、UIImageOrientation をここで放り込む実装が現実的
        // caputureVideoConnection の videoOrientation は .up に固定して初期化しているはずなので、その前提で進める。
        let imageOrientation: UIImage.Orientation
        let captureVideoOrientation = !isFollowDeviceOrientationWhenCapture ? .portrait : OrientationDetector.shared.captureVideoOrientation
        let i = UIImage.Orientation(captureVideoOrientation: captureVideoOrientation)
        if let connection = videoDataOutput.connection(with: .video), connection.isFrontCameraDevice {
            // Front Camera のときはちょっとややこしい
            imageOrientation = isMirroredImageIfFrontCamera ? i.swapLeftRight.mirrored : i.swapLeftRight
        } else {
            // Back Camera のときはそのまま使う
            imageOrientation = i
        }
        return imageOrientation
    }

    // AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate で同じ名前のメソッドという…。
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoDataOutput {
            // 無音カメラの実装
            if let silentCaptureImageCompletion = silentCaptureImageCompletion {
                self.silentCaptureImageCompletion = nil
                let image = createUIImage(from: sampleBuffer, limitSize: captureLimitSize, imageOrientation: preferredUIImageOrientationForVideoDataOutput)
                let metadata = CMCopyDictionaryOfAttachments(allocator: nil, target: sampleBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any]
                isSilentCapturingImage = false
                onMainThreadAsync {
                    silentCaptureImageCompletion(image, metadata)
                }
            }

            // videoDataOutputObservers
            for observer in videoDataOutputObservers.allObjects {
                observer.simpleCameraVideoDataOutputObserve(captureOutput: output, didOutput: sampleBuffer, from: connection)
            }
        } else if output == audioDataOutput {
            // audioDataOutputObservers
            for observer in audioDataOutputObservers.allObjects {
                observer.simpleCameraAudioDataOutputObserve(captureOutput: output, didOutput: sampleBuffer, from: connection)
            }
        }
    }

    public func captureOutput(_ captureOutput: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard captureOutput == videoDataOutput else {
            return
        }
        for observer in videoDataOutputObservers.allObjects {
            observer.simpleCameraVideoDataOutputObserve(captureOutput: captureOutput, didDrop: sampleBuffer, from: connection)
        }
    }

}

extension SimpleCamera: AVCaptureFileOutputRecordingDelegate {

    public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {

    }

    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        isRecordingMovie = false
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            defer {
                self.captureSession.commitConfiguration()
            }
            // movieFileOutput を使うと自動で videoDataOutput と audioDataOutput へのデータの流れが止まるのでこうなってる。
            self.captureSession.removeOutput(self.movieFileOutput)
            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
            }
            if self.captureSession.canAddOutput(self.audioDataOutput) {
                self.captureSession.addOutput(self.audioDataOutput)
            }
            // let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: UIApplication.shared.statusBarOrientation) ?? .portrait
            // とりあえず portrait に戻す
            let videoOrientation = AVCaptureVideoOrientation.portrait
            self.videoDataOutput.connection(with: .video)?.videoOrientation = videoOrientation
        }
    }

}

extension SimpleCamera: AVCapturePhotoCaptureDelegate {

    // Monitoring Capture Progress

    public func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        isPhotoCapturingImage = false
    }

    // Receiving Capture Results

    private var preferredUIImageOrientationForPhotoOutput: UIImage.Orientation {
        guard isRunning else {
            return .up
        }

        // AVCaptureStillImageOutput の captureStillImageAsynchronously であれば撮影直前に connection の videoOrientation を弄っても問題なかったが
        // AVCapturePhotoOutput ではどうやら弄っても効かない模様なのでここでなんとかする。
        let imageOrientation: UIImage.Orientation
        let captureVideoOrientation = !isFollowDeviceOrientationWhenCapture ? .portrait : OrientationDetector.shared.captureVideoOrientation
        let i = UIImage.Orientation(captureVideoOrientation: captureVideoOrientation)
        if let connection = photoOutput.connection(with: .video), connection.isFrontCameraDevice {
            // Front Camera のときはちょっとややこしい
            imageOrientation = isMirroredImageIfFrontCamera ? i.swapLeftRight.mirrored.rotateLeft : i.swapLeftRight.rotateRight
        } else {
            // Back Camera のときはそのまま使う
            imageOrientation = i.rotateRight
        }
        return imageOrientation
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let photoCaptureImageCompletion = photoCaptureImageCompletion else {
            return
        }
        self.photoCaptureImageCompletion = nil
        if let _ = error {
            onMainThreadAsync {
                photoCaptureImageCompletion(nil, nil)
            }
            return
        }
        guard let cgImage = photo.cgImageRepresentation() else {
            onMainThreadAsync {
                photoCaptureImageCompletion(nil, nil)
            }
            return
        }

         let rawImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: preferredUIImageOrientationForPhotoOutput)
        let scaledImage: UIImage
        if self.captureLimitSize == .zero {
            scaledImage = rawImage
        } else {
            guard let c = CIImage(image: rawImage), let i = createUIImage(from: c, limitSize: self.captureLimitSize, imageOrientation: rawImage.imageOrientation) else {
                onMainThreadAsync {
                    photoCaptureImageCompletion(nil, nil)
                }
                return
            }
            scaledImage = i
        }
        onMainThreadAsync {
            photoCaptureImageCompletion(scaledImage, photo.metadata)
        }
    }

    /*
    // LivePhoto は使わないことにする
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
    }
     */

}

#endif
