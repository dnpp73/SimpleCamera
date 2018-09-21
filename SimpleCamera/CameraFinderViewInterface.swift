import UIKit

public enum GridType: Equatable {
    case none
    case equalDistance(vertical: UInt, horizontal: UInt)

    public static var equalDistance3x3: GridType {
        get {
            return .equalDistance(vertical: 2, horizontal: 2)
        }
    }

    public var next: GridType {
        get {
            switch self {
            case .none:
                return .equalDistance3x3
            case .equalDistance(_, _):
                return .none
            }
        }
    }

    public static func ==(lhs: GridType, rhs: GridType) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.equalDistance(let lhsVertical, let lhsHorizontal), .equalDistance(let rhsVertical, let rhsHorizontal)):
            return lhsVertical == rhsVertical && lhsHorizontal == rhsHorizontal
        default:
            return false
        }
    }

}

public protocol CameraFinderViewInterface: class {

    // MARK:- for AVCaptreSession
    var captureVideoPreviewView: AVCaptureVideoPreviewView! { get }

    // MARK:- Tap to Focus, Pinch to Zoom
    var isEnabledTapToFocusAndExposure: Bool { get set } // @IBInspectable default true
    var isEnabledPinchToZoom: Bool { get set } // @IBInspectable default true

    // MARK:- Grid Setting
    var gridType: GridType { get set } // default .none
    var blackLineWidth: CGFloat { get set } // @IBInspectable default 1.0 // 白線がある場合は左右に分かれるので 0.5 ずつの線になる。
    var whiteLineWidth: CGFloat { get set } // @IBInspectable default 0.5
    var blackLineAlpha: CGFloat { get set } // @IBInspectable default 0.7
    var whiteLineAlpha: CGFloat { get set } // @IBInspectable default 1.0 // 1.0 以外の値だと下地の黒い線が見えるのと、白のクロスした部分が濃く見えてしまうので 1.0 推奨。白い線の alpha は CameraFinderView.xib の方の UIView.alpha で全体として決める感じにすると良い。

    // MARK:- Focus Exposure Indicator
    var isFollowFocusIndicatoreHiddenDeviceCapability: Bool { get set } // @IBInspectable default true
    var isFocusIndicatorHidden: Bool { get set } // @IBInspectable default false
    var isFollowExposureIndicatoreHiddenDeviceCapability: Bool { get set } // @IBInspectable default true
    var isExposureIndicatorHidden: Bool { get set } // @IBInspectable default false

    // MARK:- Shutter Animation
    func shutterCloseAnimation(duration: TimeInterval, completion: ((Bool) -> Void)?)
    func shutterOpenAnimation(duration: TimeInterval, completion: ((Bool) -> Void)?)
    func shutterCloseAndOpenAnimation(duration: TimeInterval, completion: ((Bool) -> Void)?)

    // MARK:- Custom UI
    var contentView: UIView! { get }

}
