import Foundation
import AVFoundation

internal func findCameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    for device in AVCaptureDevice.devices() where device.position == position {
        return device
    }
    return nil
}

extension AVCaptureConnection {
    internal var isFrontCameraDevice: Bool {
        // inputPorts は 1 つだけという前提（現状の iOS では全部そうなので）
        guard let device = (self.inputPorts.first?.input as? AVCaptureDeviceInput)?.device else {
            return false
        }

        switch device.position {
        case .front:
            return true
        case .back:
            return false
        case .unspecified:
            return false
        @unknown default:
            return false
        }
    }
}

extension AVCaptureDevice {

    internal func lockAndConfiguration(block configurationBlock: (Swift.Void) -> Swift.Void) {
        do {
            try lockForConfiguration()
            defer {
                unlockForConfiguration()
            }
            configurationBlock(())
        } catch let error /* as NSError */ {
            print(error)
        }
    }

    internal func lockAndConfiguration(queue: DispatchQueue, sync: Bool = true, configurationBlock: @escaping (Swift.Void) -> Swift.Void) {
        let execute = {
            do {
                try self.lockForConfiguration()
                defer {
                    self.unlockForConfiguration()
                }
                configurationBlock(())
            } catch let error /* as NSError */ {
                print(error)
            }
        }
        if sync {
            queue.sync(execute: execute)
        } else {
            queue.async(execute: execute)
        }
    }

}

extension Array where Element: AVCaptureDevice.Format {

    /*
     ピクセルフォーマットのメモ。
     420f はフルレンジ(luma=[0,255] chroma=[1,255])
     420v はビデオレンジ(luma=[16,235] chroma=[16,240])
     CMFormatDescriptionGetMediaSubType($0.formatDescription)
     420v == 875704438
     420f == 875704422
     */

    internal var fliter420v: [AVCaptureDevice.Format] {
        return filter { (format: AVCaptureDevice.Format) -> Bool in
            return CMFormatDescriptionGetMediaSubType(format.formatDescription) == 875704438
        }
    }

    internal var sortedByQuality: [AVCaptureDevice.Format] {
        return sorted { (a, b) -> Bool in
            let ad = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let a_size = ad.width * ad.height
            let bd = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            let b_size = bd.width * bd.height
            // 画角が広いのを優先して、その後にサイズ順に並べる
            if a.videoFieldOfView >= b.videoFieldOfView {
                return a_size > b_size
            } else {
                return false
            }
        }
    }

    internal var filterAspect4_3: [AVCaptureDevice.Format] {
        return filter { (format: AVCaptureDevice.Format) -> Bool in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return d.width * 3 == d.height * 4 || d.width * 4 == d.height * 3
        }
    }

    internal var filterAspect16_9: [AVCaptureDevice.Format] {
        return filter { (format: AVCaptureDevice.Format) -> Bool in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return d.width * 9 == d.height * 16 || d.width * 16 == d.height * 9
        }
    }

}
