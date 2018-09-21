import UIKit

private extension UIImage {

    convenience init?(color: UIColor, size: CGSize) {
        if size.width <= 0 || size.height <= 0 {
            self.init()
            return nil
        }

        UIGraphicsBeginImageContext(size)
        defer{
            UIGraphicsEndImageContext()
        }
        let rect = CGRect(origin: CGPoint.zero, size: size)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        context.setFillColor(color.cgColor)
        context.fill(rect)
        guard let image = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else {
            return nil
        }
        self.init(cgImage: image)
    }

}

internal final class ZoomIndicatorButton: UIButton {

    // MARK:- UIView Extension

    @IBInspectable dynamic var cornerRadius: CGFloat {
        get {
            return layer.cornerRadius
        }
        set {
            layer.cornerRadius = newValue
            layer.masksToBounds = newValue > 0
        }
    }

    @IBInspectable dynamic var borderColor: UIColor {
        get {
            return UIColor(cgColor:layer.borderColor!)
        }
        set {
            layer.borderColor = newValue.cgColor
        }
    }

    @IBInspectable dynamic var borderWidth: CGFloat {
        get {
            return layer.borderWidth
        }
        set {
            layer.borderWidth = newValue
        }
    }

    // MARK:- UIButton Extension

    private func setBackgroundColor(_ color: UIColor?, for state: UIControl.State) {
        if let color = color {
            let image = UIImage(color: color, size: bounds.size)
            setBackgroundImage(image, for: state)
        } else {
            setBackgroundImage(nil, for: state)
        }
    }

    @IBInspectable dynamic var normalBackgroundColor: UIColor? {
        get {
            return nil // dummy
        }
        set {
            setBackgroundColor(newValue, for: .normal)
        }
    }

    @IBInspectable dynamic var highlightedBackgroundColor: UIColor? {
        get {
            return nil // dummy
        }
        set {
            setBackgroundColor(newValue, for: .highlighted)
        }
    }

    @IBInspectable dynamic var disabledBackgroundColor: UIColor? {
        get {
            return nil // dummy
        }
        set {
            setBackgroundColor(newValue, for: .disabled)
        }
    }

    // MARK:- Initializer

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        updateTitleForCurrentZoomFactor()
        SimpleCamera.shared.add(simpleCameraObserver: self)
    }

    // MARK:-

    func updateTitleForCurrentZoomFactor() {
        let zoomFactor = SimpleCamera.shared.zoomFactor
        let zoomFactorString = String(format: "%.1f", zoomFactor)
        let title: String
        if zoomFactorString.hasSuffix(".0") {
            let l = zoomFactorString.count - 2
            title = zoomFactorString.prefix(l) + "x"
        } else {
            title = zoomFactorString + "x"
        }
        setTitle(title, for: .normal)
    }

}

import AVFoundation

extension ZoomIndicatorButton: SimpleCameraObservable {
    func simpleCameraDidStartRunning(simpleCamera: SimpleCamera) {}
    func simpleCameraDidStopRunning(simpleCamera: SimpleCamera) {}
    func simpleCameraDidChangeFocusPointOfInterest(simpleCamera: SimpleCamera) {}
    func simpleCameraDidChangeExposurePointOfInterest(simpleCamera: SimpleCamera) {}
    func simpleCameraDidResetFocusAndExposure(simpleCamera: SimpleCamera) {}
    func simpleCameraDidSwitchCameraInput(simpleCamera: SimpleCamera) {}
//    func simpleCameraSessionRuntimeError(simpleCamera: SimpleCamera, error: AVError) {}
//    @available(iOS 9.0, *)
//    func simpleCameraSessionWasInterrupted(simpleCamera: SimpleCamera, reason: AVCaptureSession.InterruptionReason) {}
    func simpleCameraSessionInterruptionEnded(simpleCamera: SimpleCamera) {}

    internal func simpleCameraDidChangeZoomFactor(simpleCamera: SimpleCamera) {
        updateTitleForCurrentZoomFactor()
    }
}
