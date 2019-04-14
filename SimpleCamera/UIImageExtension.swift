import UIKit

public extension UIImage {

    private func replace(imageOrientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = cgImage else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }

    var mirrored: UIImage? {
        return replace(imageOrientation: imageOrientation.mirrored)
    }

    var rotateRight: UIImage? {
        return replace(imageOrientation: imageOrientation.rotateRight)
    }

    var rotateLeft: UIImage? {
        return replace(imageOrientation: imageOrientation.rotateLeft)
    }

    var rotateUpsideDown: UIImage? {
        return replace(imageOrientation: imageOrientation.rotateUpsideDown)
    }

}
