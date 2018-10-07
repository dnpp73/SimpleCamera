import Foundation
import UIKit
import AVFoundation

// struct にしたいけど deinit が使えないのと、
// AVCaptureVideoDataOutputSampleBufferDelegate が class 指定というか NSObject 指定なのでしょうがない。
public final class SimpleCamera: NSObject, SimpleCameraInterface {

    public static let shared = SimpleCamera() // Singleton
    private override init() {}

    fileprivate let sessionQueue = DispatchQueue(label: "org.dnpp.SimpleCamera.sessionQueue") // attributes: .concurrent しなければ serial queue
    private     let videoOutputQueue = DispatchQueue(label: "org.dnpp.SimpleCamera.VideoOutput.delegateQueue")

    fileprivate let captureSession = AVCaptureSession()
    private     let imageOutput    = AVCaptureStillImageOutput()
    fileprivate let videoOutput    = AVCaptureVideoDataOutput() // extension の AVCaptureVideoDataOutputSampleBufferDelegate 内で使っているため fileprivate
    fileprivate let audioOutput    = AVCaptureAudioDataOutput() // extension の AVCaptureVideoDataOutputSampleBufferDelegate 内で使っているため fileprivate
    fileprivate let fileOutput     = AVCaptureMovieFileOutput()

    private var frontCameraVideoInput: AVCaptureDeviceInput?
    private var backCameraVideoInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?

    fileprivate var isSilentCapturingImage: Bool = false
    fileprivate var silentCaptureImageCompletion: ((_ image: UIImage?, _ metadata: [String: Any]?) -> Void)? // extension の AVCaptureVideoDataOutputSampleBufferDelegate 内で使っているため fileprivate

    private let observers: NSHashTable<SimpleCameraObservable> = NSHashTable.weakObjects()
    fileprivate let videoOutputObservers: NSHashTable<SimpleCameraVideoOutputObservable> = NSHashTable.weakObjects()
    fileprivate let audioOutputObservers: NSHashTable<SimpleCameraAudioOutputObservable> = NSHashTable.weakObjects()

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
        sessionQueue.async {
            captureVideoPreviewView.session = self.captureSession
        }
        self.captureVideoPreviewView = captureVideoPreviewView
    }

    public var isRunning: Bool {
        guard isConfigured else {
            return false
        }
        return captureSession.isRunning
    }

    public func startRunning() {
        configure() // この実行でカメラの許可ダイアログが出る

        guard isConfigured else {
            return
        }
        if !isRunning {
            OrientationDetector.shared.startSensor()
            sessionQueue.async {
                self.captureSession.startRunning()
                self.resetFocusAndExposure()
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

    private(set) public var mode: CameraMode = .unknown

    public func setPhotoMode() {
        sessionQueue.sync {
            guard isRecordingMovie == false else { return }
            guard mode != .photo else { return }

            captureSession.beginConfiguration() // defer より前の段階で commit したい

            captureSession.removeOutput(fileOutput)
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

            resetFocusAndExposure()
        }
    }

    public func setMovieMode() {
        sessionQueue.sync {
            guard isRecordingMovie == false else { return }
            guard mode != .movie else { return }

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
            // ここで fileOutput を addOutput してしまうと videoOutput に何も流れてこなくなるのでダメ。
            // 一瞬暗くなるけど録画直前に addOutput するしかなさそう。
            if captureSession.canAddOutput(fileOutput) {
                captureSession.addOutput(fileOutput)
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

            resetFocusAndExposure()
        }
    }

    // MARK: Capture Image

    public var isCapturingImage: Bool {
        get {
            return imageOutput.isCapturingStillImage || isSilentCapturingImage
        }
    }

    public var captureLimitSize: CGSize = .zero

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
        guard imageOutput.isCapturingStillImage == false else {
            completion(nil, nil)
            return
        }

        sessionQueue.async {
            let captureImageConnection: AVCaptureConnection = self.imageOutput.connection(with: .video)!
            // captureStillImageAsynchronously であれば撮影直前に connection の videoOrientation を弄っても問題なさそう
            self.captureSession.beginConfiguration()
            let videoOrientation: AVCaptureVideoOrientation
            if self.isFollowDeviceOrientationWhenCapture {
                videoOrientation = OrientationDetector.shared.captureVideoOrientation
            } else {
                videoOrientation = .portrait
            }
            captureImageConnection.videoOrientation = videoOrientation
            self.captureSession.commitConfiguration() // defer より前のタイミングで commit したい

            self.imageOutput.captureStillImageAsynchronously(from: captureImageConnection) { (imageDataBuffer, error) -> Void in
                guard let imageDataBuffer = imageDataBuffer, let data = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataBuffer) else {
                    onMainThread {
                        completion(nil, nil)
                    }
                    return
                }
                guard let rawImage = UIImage(data: data) else {
                    onMainThread {
                        completion(nil, nil)
                    }
                    return
                }

                let scaledImage: UIImage
                if self.captureLimitSize == .zero {
                    scaledImage = rawImage
                } else {
                    guard let c = CIImage(image: rawImage), let i = createUIImage(from: c, limitSize: self.captureLimitSize, imageOrientation: rawImage.imageOrientation) else {
                        onMainThread {
                            completion(nil, nil)
                        }
                        return
                    }
                    scaledImage = i
                }

                let metadata = CMCopyDictionaryOfAttachments(allocator: nil, target: imageDataBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any]
                let mirrored = self.isMirroredImageIfFrontCamera && captureImageConnection.isFrontCameraDevice
                let image = mirrored ? scaledImage.mirrored : scaledImage
                onMainThread {
                    completion(image, metadata)
                }
            }
        }

    }

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
        videoOutputQueue.sync {
            silentCaptureImageCompletion = completion
        }
    }

    // MARK: - Record Movie

    public var isEnabledAudioRecording: Bool = false

    fileprivate(set) public var isRecordingMovie: Bool = false

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
        guard captureSession.canAddOutput(fileOutput) else {
            return false
        }
        sessionQueue.sync {
            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
            }
            // fileOutput を使うと自動で videoOutput と audioOutput へのデータの流れが止まるのでこうなってる。
            captureSession.removeOutput(videoOutput)
            captureSession.removeOutput(audioOutput)
            captureSession.addOutput(fileOutput)
            let videoOrientation: AVCaptureVideoOrientation
            if self.isFollowDeviceOrientationWhenCapture {
                videoOrientation = OrientationDetector.shared.captureVideoOrientation
            } else {
                videoOrientation = .portrait
            }
            fileOutput.connection(with: .video)?.videoOrientation = videoOrientation
        }

        isRecordingMovie = true
        // videoInput, audioInput, fileOutput を captureSession に足したり消したりしてる関係で、デバイスの初期化が走ってしまい少し暗くなるので気持ちの待ちを入れる。
        sessionQueue.asyncAfter(deadline: .now() + 0.3) {
            self.fileOutput.startRecording(to: url, recordingDelegate: self)
        }
        return true
    }

    public func stopRecordMovie() {
        sessionQueue.async {
            self.fileOutput.stopRecording()
        }
    }

    // MARK: Camera Setting

    // TODO : ズームだけ実装した。ホワイトバランスや ISO やシャッタースピードの調整は後で lockCurrentCameraDeviceAndConfigure を使って作る。

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
            return device.videoZoomFactor
        }
        set {
            lockCurrentCameraDeviceAndConfigure {
                guard let lockedDevice = self.currentDevice else { return }
                let minZoomFactor = CGFloat(1.0)
                let maxZoomFactor = self.maxZoomFactor
                let validateZoomFactor = min(max(newValue, minZoomFactor), maxZoomFactor)
                lockedDevice.videoZoomFactor = validateZoomFactor
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
        get {
            guard let videoMaxZoomFactor = currentDevice?.activeFormat.videoMaxZoomFactor else {
                return 1.0
            }
            return min(zoomFactorLimit, videoMaxZoomFactor)
        }
    }

    // MARK: Focus, Exposure

    public var focusPointOfInterest: CGPoint {
        get {
            guard let device = currentDevice else {
                return CGPoint.zero
            }
            return device.focusPointOfInterest
        }
    }

    public func focus(at devicePoint: CGPoint, focusMode: AVCaptureDevice.FocusMode, monitorSubjectAreaChange: Bool) {
        lockCurrentCameraDeviceAndConfigure(sync: false) {
            guard let device = self.currentDevice else { return }
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = focusMode
            }
            device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
        }
    }

    public var exposurePointOfInterest: CGPoint {
        get {
            guard let device = currentDevice else {
                return CGPoint.zero
            }
            return device.exposurePointOfInterest
        }
    }

    public func exposure(at devicePoint: CGPoint, exposureMode: AVCaptureDevice.ExposureMode, monitorSubjectAreaChange: Bool) {
        lockCurrentCameraDeviceAndConfigure(sync: false) {
            guard let device = self.currentDevice else { return }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = exposureMode
            }
            device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
        }
    }

    public func focusAndExposure(at devicePoint: CGPoint, focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, monitorSubjectAreaChange: Bool) {
        lockCurrentCameraDeviceAndConfigure(sync: false) {
            guard let device = self.currentDevice else { return }
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
        guard let device = self.currentDevice else { return }
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
            onMainThread {
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
            videoOutput.connection(with: .video)?.videoOrientation = videoOrientation
        }

        if switchSucceed {
            // 内部で sessionQueue.async してるので外に出しておきたい
            onMainThread {
                for observer in self.observers.allObjects {
                    observer.simpleCameraDidSwitchCameraInput(simpleCamera: self)
                }
            }
            resetFocusAndExposure()
        }
    }

    public var isCurrentInputFront: Bool {
        get {
            guard let device = currentDevice else {
                return false
            }
            return device.position == .front
        }
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
        get {
            guard let device = currentDevice else {
                return false
            }
            return device.position == .back
        }
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

    // MARK: Manage VideoOutput Observer

    public func add(videoOutputObserver: SimpleCameraVideoOutputObservable) {
        if !videoOutputObservers.contains(videoOutputObserver) {
            videoOutputObservers.add(videoOutputObserver)
        }
    }

    public func remove(videoOutputObserver: SimpleCameraVideoOutputObservable) {
        if videoOutputObservers.contains(videoOutputObserver) {
            videoOutputObservers.remove(videoOutputObserver)
        }
    }

    // MARK: Manage AudioOutput Observers

    public func add(audioOutputObserver: SimpleCameraAudioOutputObservable) {
        if !audioOutputObservers.contains(audioOutputObserver) {
            audioOutputObservers.add(audioOutputObserver)
        }

    }

    public func remove(audioOutputObserver: SimpleCameraAudioOutputObservable) {
        if audioOutputObservers.contains(audioOutputObserver) {
            audioOutputObservers.remove(audioOutputObserver)
        }
    }

    // MARK: - Private Functions

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
                if let device = findCameraDevice(position: .front) {
                    frontCameraVideoInput = try AVCaptureDeviceInput(device: device)
                } else {
                    print("frontCameraVideoInput is nil")
                    frontCameraVideoInput = nil
                }
            } catch let error {
                print(error)
                print("frontCameraVideoInput is nil")
                frontCameraVideoInput = nil
            }
            do {
                if let device = findCameraDevice(position: .back) {
                    backCameraVideoInput = try AVCaptureDeviceInput(device: device)
                } else {
                    print("backCameraVideoInput is nil")
                    backCameraVideoInput = nil
                }
            } catch let error {
                print(error)
                print("backCameraVideoInput is nil")
                backCameraVideoInput = nil
            }

            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
            }

            // captureSession に imageOutput を放り込む
            imageOutput.outputSettings = [ AVVideoCodecKey: AVVideoCodecJPEG ]
            if captureSession.canAddOutput(imageOutput) {
                captureSession.addOutput(imageOutput)
            }

            // videoOutput を調整して captureSession に放り込む
            // kCVPixelBufferPixelFormatTypeKey の部分だけど、
            // Available pixel format types on this platform are (
            //     420v, // たぶん kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            //     420f,
            //     BGRA // kCVPixelFormatType_32BGRA
            // ).
            // とのこと。
            // iPhone 4s でのみ再現するんだけど、マジで何も言わずデバッガにも引っ掛からずにアプリが落ちるので
            // cameraVideoInputDevice と videoOutput のフォーマットを 420v の統一してみたところ落ちなくなった。
            videoOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange as UInt32)]
            videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }

            audioOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            if captureSession.canAddOutput(audioOutput) {
                captureSession.addOutput(audioOutput)
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

            // imageOutput と videoOutput の videoOrientation を InterfaceOrientation に揃えるか縦にしておく。
            // captureSession に addInput した後じゃないと connection は nil なので videoOrientation を取ろうとすると nil アクセスで死にます。
            // デフォルトでは imageOutput が 1 (portrait) で videoOutput が 3 (landscapeRight)
            // let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: UIApplication.shared.statusBarOrientation) ?? .portrait
            // とりあえず portrait に戻す
            let videoOrientation = AVCaptureVideoOrientation.portrait
            if let imageOutputConnection = imageOutput.connection(with: AVMediaType.video) {
                if imageOutputConnection.isVideoOrientationSupported {
                    imageOutputConnection.videoOrientation = videoOrientation
                }
                imageOutputConnection.videoScaleAndCropFactor = 1.0
            }
            if let videoOutputConnection = videoOutput.connection(with: AVMediaType.video) {
                if videoOutputConnection.isVideoOrientationSupported {
                    videoOutputConnection.videoOrientation = videoOrientation
                }
                videoOutputConnection.videoScaleAndCropFactor = 1.0
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

        videoOutputQueue.sync {
            silentCaptureImageCompletion = nil
            isSilentCapturingImage = false
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

    private var captureSessionRunningObserveContext = 0

    private var frontCameraDeviceAdjustingFocusObserveContext = 0
    private var backCameraDeviceAdjustingFocusObserveContext = 0
    private var frontCameraDeviceAdjustingExposureObserveContext = 0
    private var backCameraDeviceAdjustingExposureObserveContext = 0
    private var frontCameraDeviceAdjustingWhiteBalanceObserveContext = 0
    private var backCameraDeviceAdjustingWhiteBalanceObserveContext = 0

    private var frontCameraDeviceFocusPointOfInterestObserveContext = 0
    private var backCameraDeviceFocusPointOfInterestObserveContext = 0
    private var frontCameraDeviceExposurePointOfInterestObserveContext = 0
    private var backCameraDeviceExposurePointOfInterestObserveContext = 0

    private var frontCameraDeviceVideoZoomFactorObserveContext = 0
    private var backCameraDeviceVideoZoomFactorObserveContext = 0

    private func addObservers() {
        captureSession.addObserver(self, forKeyPath: "running", options: .new, context: &captureSessionRunningObserveContext)

        frontCameraVideoInput?.device.addObserver(self, forKeyPath: "adjustingFocus", options: .new, context: &frontCameraDeviceAdjustingFocusObserveContext)
        backCameraVideoInput?.device.addObserver(self, forKeyPath: "adjustingFocus", options: .new, context: &backCameraDeviceAdjustingFocusObserveContext)
        frontCameraVideoInput?.device.addObserver(self, forKeyPath: "adjustingExposure", options: .new, context: &frontCameraDeviceAdjustingExposureObserveContext)
        backCameraVideoInput?.device.addObserver(self, forKeyPath: "adjustingExposure", options: .new, context: &backCameraDeviceAdjustingExposureObserveContext)
        frontCameraVideoInput?.device.addObserver(self, forKeyPath: "adjustingWhiteBalance", options: .new, context: &frontCameraDeviceAdjustingWhiteBalanceObserveContext)
        backCameraVideoInput?.device.addObserver(self, forKeyPath: "adjustingWhiteBalance", options: .new, context: &backCameraDeviceAdjustingWhiteBalanceObserveContext)

        frontCameraVideoInput?.device.addObserver(self, forKeyPath: "focusPointOfInterest", options: .new, context: &frontCameraDeviceFocusPointOfInterestObserveContext)
        backCameraVideoInput?.device.addObserver(self, forKeyPath: "focusPointOfInterest", options: .new, context: &backCameraDeviceFocusPointOfInterestObserveContext)
        frontCameraVideoInput?.device.addObserver(self, forKeyPath: "exposurePointOfInterest", options: .new, context: &frontCameraDeviceExposurePointOfInterestObserveContext)
        backCameraVideoInput?.device.addObserver(self, forKeyPath: "exposurePointOfInterest", options: .new, context: &backCameraDeviceExposurePointOfInterestObserveContext)

        frontCameraVideoInput?.device.addObserver(self, forKeyPath: "videoZoomFactor", options: .new, context: &frontCameraDeviceVideoZoomFactorObserveContext)
        backCameraVideoInput?.device.addObserver(self, forKeyPath: "videoZoomFactor", options: .new, context: &backCameraDeviceVideoZoomFactorObserveContext)

        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: Notification.Name("AVCaptureDeviceSubjectAreaDidChangeNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: Notification.Name("AVCaptureSessionRuntimeErrorNotification"), object: captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: Notification.Name("AVCaptureSessionWasInterruptedNotification"), object: captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: Notification.Name("AVCaptureSessionInterruptionEndedNotification"), object: captureSession)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)

        captureSession.removeObserver(self, forKeyPath: "running", context: &captureSessionRunningObserveContext)

        frontCameraVideoInput?.device.removeObserver(self, forKeyPath: "adjustingFocus", context: &frontCameraDeviceAdjustingFocusObserveContext)
        backCameraVideoInput?.device.removeObserver(self, forKeyPath: "adjustingFocus", context: &backCameraDeviceAdjustingFocusObserveContext)
        frontCameraVideoInput?.device.removeObserver(self, forKeyPath: "adjustingExposure", context: &frontCameraDeviceAdjustingExposureObserveContext)
        backCameraVideoInput?.device.removeObserver(self, forKeyPath: "adjustingExposure", context: &backCameraDeviceAdjustingExposureObserveContext)
        frontCameraVideoInput?.device.removeObserver(self, forKeyPath: "adjustingWhiteBalance", context: &frontCameraDeviceAdjustingWhiteBalanceObserveContext)
        backCameraVideoInput?.device.removeObserver(self, forKeyPath: "adjustingWhiteBalance", context: &backCameraDeviceAdjustingWhiteBalanceObserveContext)

        frontCameraVideoInput?.device.removeObserver(self, forKeyPath: "focusPointOfInterest", context: &frontCameraDeviceFocusPointOfInterestObserveContext)
        backCameraVideoInput?.device.removeObserver(self, forKeyPath: "focusPointOfInterest", context: &backCameraDeviceFocusPointOfInterestObserveContext)
        frontCameraVideoInput?.device.removeObserver(self, forKeyPath: "exposurePointOfInterest", context: &frontCameraDeviceExposurePointOfInterestObserveContext)
        backCameraVideoInput?.device.removeObserver(self, forKeyPath: "exposurePointOfInterest", context: &backCameraDeviceExposurePointOfInterestObserveContext)

        frontCameraVideoInput?.device.removeObserver(self, forKeyPath: "videoZoomFactor", context: &frontCameraDeviceVideoZoomFactorObserveContext)
        backCameraVideoInput?.device.removeObserver(self, forKeyPath: "videoZoomFactor", context: &backCameraDeviceVideoZoomFactorObserveContext)
    }

    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context == &captureSessionRunningObserveContext {
            guard let isRunning = (change?[.newKey] as AnyObject?)?.boolValue else { return }
            onMainThread {
                self.isRunningForObserve = isRunning
            }
        } else if context == &frontCameraDeviceAdjustingFocusObserveContext {
            // guard let isAdjustingFocus = (change?[.newKey] as AnyObject?)?.boolValue else { return }
            // print("[KVO] frontCameraDevice adjustingFocus: \(isAdjustingFocus)")
        } else if context == &backCameraDeviceAdjustingFocusObserveContext {
            // guard let isAdjustingFocus = (change?[.newKey] as AnyObject?)?.boolValue else { return }
            // print("[KVO] backCameraDevice adjustingFocus: \(isAdjustingFocus)")
        } else if context == &frontCameraDeviceAdjustingExposureObserveContext {
            // guard let isAdjustingExposure = (change?[.newKey] as AnyObject?)?.boolValue else { return }
            // print("[KVO] frontCameraDevice adjustingExposure: \(isAdjustingExposure)")
        } else if context == &backCameraDeviceAdjustingExposureObserveContext {
            // guard let isAdjustingExposure = (change?[.newKey] as AnyObject?)?.boolValue else { return }
            // print("[KVO] backCameraDevice adjustingExposure: \(isAdjustingExposure)")
        } else if context == &frontCameraDeviceAdjustingWhiteBalanceObserveContext {
            // guard let isAdjustingWhiteBalance = (change?[.newKey] as AnyObject?)?.boolValue else { return }
            // print("[KVO] frontCameraDevice adjustingWhiteBalance: \(isAdjustingWhiteBalance)")
            // 白色点を清く正しく取ってくるの、色々ありそうなのでめんどくさそう。Dash で 'AVCaptureDevice white' くらいまで打てば出てくる英語を読まないといけない。
        } else if context == &backCameraDeviceAdjustingWhiteBalanceObserveContext {
            // guard let isAdjustingWhiteBalance = (change?[.newKey] as AnyObject?)?.boolValue else { return }
            // print("[KVO] backCameraDevice adjustingWhiteBalance: \(isAdjustingWhiteBalance)")
            // 白色点を清く正しく取ってくるの、色々ありそうなのでめんどくさそう。Dash で 'AVCaptureDevice white' くらいまで打てば出てくる英語を読まないといけない。
        } else if context == &frontCameraDeviceFocusPointOfInterestObserveContext {
            guard let focusPointOfInterest = (change?[.newKey] as AnyObject?)?.cgPointValue else { return }
            onMainThread {
                self.focusPointOfInterestForObserve = focusPointOfInterest
            }
        } else if context == &backCameraDeviceFocusPointOfInterestObserveContext {
            guard let focusPointOfInterest = (change?[.newKey] as AnyObject?)?.cgPointValue else { return }
            onMainThread {
                self.focusPointOfInterestForObserve = focusPointOfInterest
            }
        } else if context == &frontCameraDeviceExposurePointOfInterestObserveContext {
            guard let exposurePointOfInterest = (change?[.newKey] as AnyObject?)?.cgPointValue else { return }
            onMainThread {
                self.exposurePointOfInterestForObserve = exposurePointOfInterest
            }
        } else if context == &backCameraDeviceExposurePointOfInterestObserveContext {
            guard let exposurePointOfInterest = (change?[.newKey] as AnyObject?)?.cgPointValue else { return }
            onMainThread {
                self.exposurePointOfInterestForObserve = exposurePointOfInterest
            }
        } else if context == &frontCameraDeviceVideoZoomFactorObserveContext {
            guard let videoZoomFactor = (change?[.newKey] as AnyObject?)?.doubleValue else { return }
            onMainThread {
                self.zoomFactorForObserve = CGFloat(videoZoomFactor)
            }
        } else if context == &backCameraDeviceVideoZoomFactorObserveContext {
            guard let videoZoomFactor = (change?[.newKey] as AnyObject?)?.doubleValue else { return }
            onMainThread {
                self.zoomFactorForObserve = CGFloat(videoZoomFactor)
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    @objc private func subjectAreaDidChange(notification: Notification) {
        // print("Subject Area Did Change")
        if let device = notification.object as? AVCaptureDevice, device == currentDevice {
            // print("notification.object == currentDevice")
            resetFocusAndExposure()
        }
    }

    @objc private func sessionRuntimeError(notification: Notification) {
        // TODO
        /*
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        let error = AVError(_nsError: errorValue)
        onMainThread {
            for observer in self.observers.allObjects {
                observer.simpleCameraSessionRuntimeError(simpleCamera: self, error: error)
            }
        }
         */
    }

    @objc private func sessionWasInterrupted(notification: Notification) {
        // TODO
        /*
        guard #available(iOS 9.0, *) else {
            return
        }
        guard let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?, let reasonIntegerValue = userInfoValue.integerValue, let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) else {
            return
        }
        onMainThread {
            for observer in self.observers.allObjects {
                observer.simpleCameraSessionWasInterrupted(simpleCamera: self, reason: reason)
            }
        }
         */
    }

    @objc private func sessionInterruptionEnded(notification: Notification) {
        onMainThread {
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

    public var preferredUIImageOrientationForVideoOutput: UIImage.Orientation {
        get {
            guard isRunning else {
                return .up
            }

            // 撮影直前に connection の videoOrientation を弄ると実用的に問題があるので、UIImageOrientation をここで放り込む実装が現実的
            // caputureVideoConnection の videoOrientation は .up に固定して初期化しているはずなので、その前提で進める。
            let imageOrientation: UIImage.Orientation
            let captureVideoOrientation = !isFollowDeviceOrientationWhenCapture ? .portrait : OrientationDetector.shared.captureVideoOrientation
            let i = UIImage.Orientation(captureVideoOrientation: captureVideoOrientation)
            if let connection = videoOutput.connection(with: .video), connection.isFrontCameraDevice {
                // Front Camera のときはちょっとややこしい
                imageOrientation = isMirroredImageIfFrontCamera ? i.swapLeftRight.mirrored : i.swapLeftRight
            } else {
                // Back Camera のときはそのまま使う
                imageOrientation = i
            }
            return imageOrientation
        }
    }

    // AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate で同じ名前のメソッドという…。
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoOutput {
            // 無音カメラの実装
            if let silentCaptureImageCompletion = silentCaptureImageCompletion {
                self.silentCaptureImageCompletion = nil
                let image = createUIImage(from: sampleBuffer, limitSize: captureLimitSize, imageOrientation: preferredUIImageOrientationForVideoOutput)
                let metadata = CMCopyDictionaryOfAttachments(allocator: nil, target: sampleBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any]
                isSilentCapturingImage = false
                onMainThread {
                    silentCaptureImageCompletion(image, metadata)
                }
            }

            // videoOutputObservers
            for observer in videoOutputObservers.allObjects {
                observer.simpleCameraVideoOutputObserve(captureOutput: output, didOutput: sampleBuffer, from: connection)
            }
        } else if output == audioOutput {
            // audioOutputObservers
            for observer in audioOutputObservers.allObjects {
                observer.simpleCameraAudioOutputObserve(captureOutput: output, didOutput: sampleBuffer, from: connection)
            }
        }
    }

    public func captureOutput(_ captureOutput: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard captureOutput == videoOutput else { return }
        for observer in videoOutputObservers.allObjects {
            observer.simpleCameraVideoOutputObserve(captureOutput: captureOutput, didDrop: sampleBuffer, from: connection)
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
            // fileOutput を使うと自動で videoOutput と audioOutput へのデータの流れが止まるのでこうなってる。
            self.captureSession.removeOutput(self.fileOutput)
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            if self.captureSession.canAddOutput(self.audioOutput) {
                self.captureSession.addOutput(self.audioOutput)
            }
            // let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: UIApplication.shared.statusBarOrientation) ?? .portrait
            // とりあえず portrait に戻す
            let videoOrientation = AVCaptureVideoOrientation.portrait
            self.videoOutput.connection(with: .video)?.videoOrientation = videoOrientation
        }
    }

}
