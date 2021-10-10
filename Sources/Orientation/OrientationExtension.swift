#if canImport(UIKit)

import Foundation
import UIKit
import AVFoundation

public extension AVCaptureVideoOrientation {

    init?(deviceOrientation: UIDeviceOrientation) {
        // UIDeviceOrientation.landscapeLeft  と AVCaptureVideoOrientation.landscapeRight
        // UIDeviceOrientation.landscapeRight と AVCaptureVideoOrientation.landscapeLeft
        // がそれぞれ対応するのでややこしい。ドキュメントと定義部分のコメントを読むとホームボタン基準でどうなってるかが書かれていて分かりやすい。
        switch deviceOrientation {
        case .portrait:           self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft:      self = .landscapeRight
        case .landscapeRight:     self = .landscapeLeft
        default: return nil // faceUp と faceDown は未定義
        }
    }

    // UIInterfaceOrientation については定義部分のコメントに
    // Note that UIInterfaceOrientationLandscapeLeft is equal to UIDeviceOrientationLandscapeRight (and vice versa).
    // This is because rotating the device to the left requires rotating the content to the right.
    // とあるので、Left と Right の対応はこれで良い。
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:           self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeRight:     self = .landscapeRight
        case .landscapeLeft:      self = .landscapeLeft
        default: return nil
        }
    }

}

public extension UIImage.Orientation {

    var mirrored: UIImage.Orientation {
        switch self {
        case .up:            return .upMirrored
        case .down:          return .downMirrored
        case .left:          return .rightMirrored
        case .right:         return .leftMirrored
        case .upMirrored:    return .up
        case .downMirrored:  return .down
        case .leftMirrored:  return .right
        case .rightMirrored: return .left
        @unknown default:    fatalError("unknown UIImage.Orientation")
        }
    }

    var rotateRight: UIImage.Orientation {
        switch self {
        case .up:            return .right
        case .down:          return .left
        case .left:          return .up
        case .right:         return .down
        case .upMirrored:    return .rightMirrored
        case .downMirrored:  return .leftMirrored
        case .leftMirrored:  return .upMirrored
        case .rightMirrored: return .downMirrored
        @unknown default:    fatalError("unknown UIImage.Orientation")
        }
    }

    var rotateLeft: UIImage.Orientation {
        switch self {
        case .up:            return .left
        case .down:          return .right
        case .left:          return .down
        case .right:         return .up
        case .upMirrored:    return .leftMirrored
        case .downMirrored:  return .rightMirrored
        case .leftMirrored:  return .downMirrored
        case .rightMirrored: return .upMirrored
        @unknown default:    fatalError("unknown UIImage.Orientation")
        }
    }

    var rotateUpsideDown: UIImage.Orientation {
        switch self {
        case .up:            return .down
        case .down:          return .up
        case .left:          return .right
        case .right:         return .left
        case .upMirrored:    return .downMirrored
        case .downMirrored:  return .upMirrored
        case .leftMirrored:  return .rightMirrored
        case .rightMirrored: return .leftMirrored
        @unknown default:    fatalError("unknown UIImage.Orientation")
        }
    }

    var swapLeftRight: UIImage.Orientation {
        switch self {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .right
        case .right:         return .left
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .rightMirrored
        case .rightMirrored: return .leftMirrored
        @unknown default:    fatalError("unknown UIImage.Orientation")
        }
    }

    init(captureVideoOrientation: AVCaptureVideoOrientation) {
        switch captureVideoOrientation {
        case .portrait:           self = .up
        case .portraitUpsideDown: self = .down
        case .landscapeRight:     self = .left
        case .landscapeLeft:      self = .right
        @unknown default:    fatalError("unknown AVCaptureVideoOrientation")
        }
    }

}

#endif
