import Foundation
import UIKit
import AVFoundation
import CoreImage

// MARK:- CMSampleBuffer to CIImage

public func createCIImage(from sampleBuffer: CMSampleBuffer) -> CIImage? {
    guard CMSampleBufferIsValid(sampleBuffer) else {
        return nil
    }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        return nil
    }

    return CIImage(cvPixelBuffer: pixelBuffer)
}

// MARK:- CIContext

private let cicontext = CIContext(options: [.useSoftwareRenderer: false])

// MARK:- Image Scale

public func createUIImage(from ciImage: CIImage, imageScale: CGFloat = 1.0, imageOrientation: UIImage.Orientation = .up) -> UIImage? {
    // ただアフィン変換を適用するだけなら CIFilter の CILanczosScaleTransform は遅い
    // let filter = CIFilter(name: "CILanczosScaleTransform")!
    // filter.setValue(ciImage, forKey: "inputImage")
    // filter.setValue(imageScale, forKey: "inputScale")
    // filter.setValue(1.0, forKey: "inputAspectRatio")
    // let scaledCIImage = filter.value(forKey: "outputImage") as! CIImage
    let scaledCIImage = ciImage.transformed(by: CGAffineTransform(scaleX: imageScale, y: imageScale))

    // 一度 rect を作ってから CGImage を経由して UIImage を作らないとアスペクト比が壊れてしまう
    guard let cgimage = cicontext.createCGImage(scaledCIImage, from: scaledCIImage.extent) else {
        return nil
    }
    return UIImage(cgImage: cgimage, scale: 1.0, orientation: imageOrientation)

    // これだとアスペクト比が壊れてしまう。
    // return UIImage(ciImage: scaledCIImage, scale: UIScreen.main.scale, orientation: imageOrientation)
}

public func createUIImage(from sampleBuffer: CMSampleBuffer, imageScale: CGFloat = 1.0, imageOrientation: UIImage.Orientation = .up) -> UIImage? {
    guard let image = createCIImage(from: sampleBuffer) else {
        return nil
    }
    return createUIImage(from: image, imageScale: imageScale, imageOrientation: imageOrientation)
}

// MARK:- Limit Size

public func createUIImage(from ciImage: CIImage, limitSize: CGSize = .zero, imageOrientation: UIImage.Orientation = .up) -> UIImage? {
    let imageScale: CGFloat
    if limitSize == .zero {
        imageScale = 1.0
    } else {
        let limitWidth  = limitSize.width
        let limitHeight = limitSize.height
        let imageWidth  = ciImage.extent.width
        let imageHeight = ciImage.extent.height
        let scaleWidth  = limitWidth / imageWidth
        let scaleHeight = limitHeight / imageHeight
        let scale = min(scaleWidth, scaleHeight)
        imageScale = min(1.0, scale)
    }
    return createUIImage(from: ciImage, imageScale: imageScale, imageOrientation: imageOrientation)
}

public func createUIImage(from sampleBuffer: CMSampleBuffer, limitSize: CGSize = .zero, imageOrientation: UIImage.Orientation = .up) -> UIImage? {
    guard let image = createCIImage(from: sampleBuffer) else {
        return nil
    }
    return createUIImage(from: image, limitSize: limitSize, imageOrientation: imageOrientation)
}
