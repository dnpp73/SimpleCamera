import UIKit

public extension UIImage {
    
    private func replace(imageOrientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
    
    public var mirrored: UIImage? {
        get {
            return replace(imageOrientation: imageOrientation.mirrored)
        }
    }
    
    public var rotateRight: UIImage? {
        get {
            return replace(imageOrientation: imageOrientation.rotateRight)
        }
    }
    
    public var rotateLeft: UIImage? {
        get {
            return replace(imageOrientation: imageOrientation.rotateLeft)
        }
    }
    
    public var rotateUpsideDown: UIImage? {
        get {
            return replace(imageOrientation: imageOrientation.rotateUpsideDown)
        }
    }
    
}
