#if canImport(UIKit)

import UIKit
import AVFoundation

public final class AVCaptureVideoPreviewView: UIView {

    // MARK: - AVCaptureVideoPreviewLayer

    override public class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast
    }

    // MARK: - AVCaptureVideoPreviewLayer Property Bridge

    public var videoGravity: AVLayerVideoGravity {
        get {
            captureVideoPreviewLayer.videoGravity
        }
        set {
            captureVideoPreviewLayer.videoGravity = newValue
        }
    }

    public var session: AVCaptureSession? {
        get {
            captureVideoPreviewLayer.session
        }
        set {
            captureVideoPreviewLayer.session = newValue
        }
    }

    public var connection: AVCaptureConnection? {
        captureVideoPreviewLayer.connection
    }

    // MARK: - UIView

    override public var contentMode: UIView.ContentMode {
        didSet {
            // 何故か CoreAnimation の暗黙の action っぽいアニメーションが走るので
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer {
                CATransaction.commit()
            }
            switch contentMode {
            case .scaleToFill:     videoGravity = .resize
            case .scaleAspectFit:  videoGravity = .resizeAspect
            case .scaleAspectFill: videoGravity = .resizeAspectFill
            default:               videoGravity = .resizeAspect // AVCaptureVideoPreviewLayer's Default
            }
        }
    }

}

#endif
