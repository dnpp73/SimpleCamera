import UIKit
import AVFoundation

public final class AVCaptureVideoPreviewView: UIView {
    
    // MARK:- AVCaptureVideoPreviewLayer
    
    override public class var layerClass : AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    public var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer {
        get {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }
    
    // MARK:- AVCaptureVideoPreviewLayer Property Bridge
    
    public var videoGravity: AVLayerVideoGravity {
        get {
            return captureVideoPreviewLayer.videoGravity
        }
        set {
            captureVideoPreviewLayer.videoGravity = newValue
        }
    }
    
    public var session: AVCaptureSession? {
        get {
            return captureVideoPreviewLayer.session
        }
        set {
            captureVideoPreviewLayer.session = newValue
        }
    }
    
    public var connection: AVCaptureConnection? {
        get {
            return captureVideoPreviewLayer.connection
        }
    }
    
    // MARK:- UIView
    
    public override var contentMode: UIView.ContentMode {
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
