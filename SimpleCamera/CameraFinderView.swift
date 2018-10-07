import UIKit
import AVFoundation

public final class CameraFinderView: UIView, CameraFinderViewInterface {

    // MARK: - IBOutlet

    // swiftlint:disable private_outlet
    @IBOutlet private(set) public weak var captureVideoPreviewView: AVCaptureVideoPreviewView!
    @IBOutlet private(set) public weak var contentView: UIView!
    // swiftlint:enable private_outlet

    @IBOutlet fileprivate weak var gridView: GridView!
    @IBOutlet fileprivate weak var focusIndicatorView: FocusIndicatorView!
    @IBOutlet fileprivate weak var exposureIndicatorView: ExposureIndicatorView!
    @IBOutlet fileprivate weak var zoomIndicatorButton: ZoomIndicatorButton!
    @IBOutlet fileprivate weak var shutterAnimationView: ShutterAnimationView!

    @IBOutlet fileprivate weak var captureVideoPreviewViewTapGestureRecognizer: UITapGestureRecognizer!
    @IBOutlet fileprivate weak var captureVideoPreviewViewPinchGestureRecognizer: UIPinchGestureRecognizer!

    // MARK: - UIView

    public override var contentMode: UIView.ContentMode {
        didSet {
            updateSubviewContentModes()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if let _ = window {
            updateSubviewContentModes()
        }
    }

    private func updateSubviewContentModes() {
        if let captureVideoPreviewView = captureVideoPreviewView {
            captureVideoPreviewView.contentMode = contentMode
        }
        if let gridView = gridView {
            gridView.contentMode = contentMode
            setNeedsLayout()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if let gridView = gridView {
            gridView.bounds = CGRect(origin: .zero, size: gridViewSize)
            gridView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    private var gridRatio: CGFloat? {
        if let input = captureVideoPreviewView?.captureVideoPreviewLayer.connection?.inputPorts.first?.input as? AVCaptureDeviceInput {
            let d = CMVideoFormatDescriptionGetDimensions(input.device.activeFormat.formatDescription)
            return CGFloat(d.width) / CGFloat(d.height)
        } else {
            return nil
        }
    }

    private var gridViewSize: CGSize {
        guard let gridRatio = gridRatio else {
            return bounds.size
        }

        let originalSize = bounds.size
        let aspectSize1 = CGSize(width: originalSize.width, height: originalSize.width * gridRatio)
        let aspectSize2 = CGSize(width: originalSize.height / gridRatio, height: originalSize.height)
        let minSize: CGSize
        let maxSize: CGSize
        let s1 = aspectSize1.width * aspectSize1.height
        let s2 = aspectSize2.width * aspectSize2.height
        if s1 < s2 {
            minSize = aspectSize1
            maxSize = aspectSize2
        } else {
            minSize = aspectSize2
            maxSize = aspectSize1
        }
        switch contentMode {
        case .scaleAspectFit:
            return minSize
        case .scaleAspectFill:
            return maxSize
        default:
            return originalSize
        }
    }

    // MARK: - Initializer

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupSubviewsFromXib()
        SimpleCamera.shared.add(simpleCameraObserver: self)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviewsFromXib()
        SimpleCamera.shared.add(simpleCameraObserver: self)
    }

    private func setupSubviewsFromXib() {
        let klass = type(of: self)
        guard let klassName = NSStringFromClass(klass).components(separatedBy: ".").last else {
            return
        }
        guard let subviewContainer = UINib(nibName: klassName, bundle: Bundle(for: klass)).instantiate(withOwner: self, options: nil).first as? UIView else {
            return
        }
        subviewContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subviewContainer.frame = bounds
        addSubview(subviewContainer)
        updateZoomIndicatorButtonHidden()
    }

    fileprivate func updateZoomIndicatorButtonHidden() {
        zoomIndicatorButton.isHidden = !(SimpleCamera.shared.maxZoomFactor > 1.0)
    }

    // MARK: - IBActions

    @IBAction private func handleFocusAndExposeTapGestureRecognizer(_ gestureRecognizer: UITapGestureRecognizer) {
        // captureVideoPreviewView の contentMode もとい videoGravity に応じて正しい CGPoint が返ってきてるように見えるので大丈夫そう。
        let viewPoint = gestureRecognizer.location(in: gestureRecognizer.view)
        let devicePoint = captureVideoPreviewView.captureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
        let x: Double = Double(devicePoint.x) - 0.5
        let y: Double = Double(devicePoint.y) - 0.5
        let distance: Double = sqrt( pow(x, 2.0) + pow(y, 2.0) )
        if distance > 0.05 {
            SimpleCamera.shared.focusAndExposure(at: devicePoint, focusMode: .continuousAutoFocus, exposureMode: .continuousAutoExposure, monitorSubjectAreaChange: true)
        } else {
            SimpleCamera.shared.resetFocusAndExposure()
        }
    }

    private var beforeZoomFactor: CGFloat = 1.0

    @IBAction private func handleZoomPinchGestureRecognizer(_ gestureRecognizer: UIPinchGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            zoomIndicatorButton.isEnabled = false
            beforeZoomFactor = SimpleCamera.shared.zoomFactor
        case .changed:
            let zoomFactor = beforeZoomFactor * gestureRecognizer.scale
            SimpleCamera.shared.zoomFactor = zoomFactor
        case .ended, .failed, .cancelled:
            zoomIndicatorButton.isEnabled = true
            SimpleCamera.shared.resetFocusAndExposure()
        case .possible:
            break
        }
    }

    @IBAction private func touchUpInsideZoomIndicatorButton(_ sender: ZoomIndicatorButton) {
        if SimpleCamera.shared.zoomFactor == 1.0 {
            SimpleCamera.shared.zoomFactor = 2.0
        } else {
            SimpleCamera.shared.zoomFactor = 1.0
        }
        SimpleCamera.shared.resetFocusAndExposure()
    }

    // MARK: - Tap to Focus, Pinch to Zoom

    @IBInspectable public var isEnabledTapToFocusAndExposure: Bool {
        get {
            guard let captureVideoPreviewViewTapGestureRecognizer = captureVideoPreviewViewTapGestureRecognizer else {
                return false
            }
            return captureVideoPreviewViewTapGestureRecognizer.isEnabled
        }
        set {
            captureVideoPreviewViewTapGestureRecognizer?.isEnabled = newValue
        }
    }

    @IBInspectable public var isEnabledPinchToZoom: Bool {
        get {
            guard let captureVideoPreviewViewPinchGestureRecognizer = captureVideoPreviewViewPinchGestureRecognizer else {
                return false
            }
            return captureVideoPreviewViewPinchGestureRecognizer.isEnabled
        }
        set {
            captureVideoPreviewViewPinchGestureRecognizer?.isEnabled = newValue
        }
    }

    // MARK: - GridView Property Bridge

    public var gridType: GridType {
        get {
            return gridView.gridType
        }
        set {
            gridView.gridType = newValue
            setNeedsLayout()
        }
    }

    @IBInspectable public var blackLineWidth: CGFloat {
        get {
            return gridView.blackLineWidth
        }
        set {
            gridView.blackLineWidth = newValue
            setNeedsLayout()
        }
    }

    @IBInspectable public var whiteLineWidth: CGFloat {
        get {
            return gridView.whiteLineWidth
        }
        set {
            gridView.whiteLineWidth = newValue
            setNeedsLayout()
        }
    }

    @IBInspectable public var blackLineAlpha: CGFloat {
        get {
            return gridView.blackLineAlpha
        }
        set {
            gridView.blackLineAlpha = newValue
            setNeedsLayout()
        }
    }

    @IBInspectable public var whiteLineAlpha: CGFloat {
        get {
            return gridView.whiteLineAlpha
        }
        set {
            gridView.whiteLineAlpha = newValue
            setNeedsLayout()
        }
    }

    // MARK: - Focus Exposure Indicator

    @IBInspectable public var isFollowFocusIndicatoreHiddenDeviceCapability: Bool = true {
        didSet {
            updateFocusIndicatorHidden()
        }
    }

    @IBInspectable public var isFollowExposureIndicatoreHiddenDeviceCapability: Bool = true {
        didSet {
            updateExposureIndicatorHidden()
        }
    }

    @IBInspectable public var isFocusIndicatorHidden: Bool {
        get {
            return focusIndicatorView.isHidden
        }
        set {
            focusIndicatorView.isHidden = newValue
        }
    }

    @IBInspectable public var isExposureIndicatorHidden: Bool {
        get {
            return exposureIndicatorView.isHidden
        }
        set {
            exposureIndicatorView.isHidden = newValue
        }
    }

    fileprivate func updateFocusIndicatorHidden() {
        if isFollowFocusIndicatoreHiddenDeviceCapability, let shown = SimpleCamera.shared.currentDevice?.isFocusPointOfInterestSupported {
            isFocusIndicatorHidden = !shown
        }
    }

    fileprivate func updateExposureIndicatorHidden() {
        if isFollowExposureIndicatoreHiddenDeviceCapability, let shown = SimpleCamera.shared.currentDevice?.isExposurePointOfInterestSupported {
            isExposureIndicatorHidden = !shown
        }
    }

    // MARK: - Shutter Animation

    public func shutterCloseAnimation(duration: TimeInterval, completion: ((Bool) -> Void)?) {
        shutterAnimationView.shutterCloseAnimation(duration: duration, completion: completion)
    }

    public func shutterOpenAnimation(duration: TimeInterval, completion: ((Bool) -> Void)?) {
        shutterAnimationView.shutterOpenAnimation(duration: duration, completion: completion)
    }

    public func shutterCloseAndOpenAnimation(duration: TimeInterval = 0.1, completion: ((Bool) -> Void)? = nil) {
        shutterCloseAnimation(duration: duration / 2.0) { (finished: Bool) -> Void in
            self.shutterOpenAnimation(duration: duration / 2.0, completion: completion)
        }
    }

}

extension CameraFinderView: SimpleCameraObservable {

    public func simpleCameraDidStopRunning(simpleCamera: SimpleCamera) {}
    public func simpleCameraDidChangeZoomFactor(simpleCamera: SimpleCamera) {}
//    public func simpleCameraSessionRuntimeError(simpleCamera: SimpleCamera, error: AVError) {}
//    @available(iOS 9.0, *)
//    public func simpleCameraSessionWasInterrupted(simpleCamera: SimpleCamera, reason: AVCaptureSession.InterruptionReason) {}
    public func simpleCameraSessionInterruptionEnded(simpleCamera: SimpleCamera) {}

    public func simpleCameraDidStartRunning(simpleCamera: SimpleCamera) {
        updateZoomIndicatorButtonHidden()
    }

    public func simpleCameraDidChangeFocusPointOfInterest(simpleCamera: SimpleCamera) {
        let point = captureVideoPreviewView.captureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: simpleCamera.focusPointOfInterest)
        if !point.x.isNaN && !point.y.isNaN {
            focusIndicatorView.focusAnimation(to: point)
        }
    }

    public func simpleCameraDidChangeExposurePointOfInterest(simpleCamera: SimpleCamera) {
        let point = captureVideoPreviewView.captureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: simpleCamera.exposurePointOfInterest)
        if !point.x.isNaN && !point.y.isNaN {
            exposureIndicatorView.exposureAnimation(to: point)
        }
    }

    public func simpleCameraDidResetFocusAndExposure(simpleCamera: SimpleCamera) {
        focusIndicatorView.focusResetAnimation()
        exposureIndicatorView.exposureResetAnimation()
    }

    public func simpleCameraDidSwitchCameraInput(simpleCamera: SimpleCamera) {
        updateFocusIndicatorHidden()
        updateExposureIndicatorHidden()
        updateZoomIndicatorButtonHidden()
        focusIndicatorView.focusResetAnimation(animated: false)
        exposureIndicatorView.exposureResetAnimation(animated: false)
    }

}
