#if canImport(UIKit)

import UIKit

public extension UIImage {

    private func replace(imageOrientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = cgImage else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }

    var mirrored: UIImage? {
        replace(imageOrientation: imageOrientation.mirrored)
    }

    var rotateRight: UIImage? {
        replace(imageOrientation: imageOrientation.rotateRight)
    }

    var rotateLeft: UIImage? {
        replace(imageOrientation: imageOrientation.rotateLeft)
    }

    var rotateUpsideDown: UIImage? {
        replace(imageOrientation: imageOrientation.rotateUpsideDown)
    }

}

#endif
