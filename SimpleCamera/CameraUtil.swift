import Foundation
import AVFoundation

func findCameraDevice(position: AVCaptureDevicePosition) -> AVCaptureDevice? {
    for device in AVCaptureDevice.devices() {
        if let device = device as? AVCaptureDevice , device.position == position {
            return device
        }
    }
    return nil
}

func isFrontCameraDevice(captureConnection: AVCaptureConnection) -> Bool {
    // inputPorts は 1 つだけという前提（現状の iOS では全部そうなので）
    guard let device = ((captureConnection.inputPorts.first as? AVCaptureInputPort)?.input as? AVCaptureDeviceInput)?.device else {
        return false
    }
    
    switch device.position {
    case .front:
        return true
    case .back:
        return false
    case .unspecified:
        return false
    }
}

extension AVCaptureDevice {
    
    func lockAndConfigurationWith(block configurationBlock: (Swift.Void) -> Swift.Void) {
        do {
            try lockForConfiguration()
            defer {
                unlockForConfiguration()
            }
            configurationBlock()
        }
        catch let error /* as NSError */ {
            print(error)
        }
    }
    
    func lockAndConfigurationWith(queue: DispatchQueue, sync: Bool = true, configurationBlock: @escaping (Swift.Void) -> Swift.Void) {
        let execute = {
            do {
                try self.lockForConfiguration()
                defer {
                    self.unlockForConfiguration()
                }
                configurationBlock()
            }
            catch let error /* as NSError */ {
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

extension Array where Element : AVCaptureDeviceFormat {
    
    /*
     ピクセルフォーマットのメモ。
     420f はフルレンジ(luma=[0,255] chroma=[1,255])
     420v はビデオレンジ(luma=[16,235] chroma=[16,240])
     CMFormatDescriptionGetMediaSubType($0.formatDescription)
     420v == 875704438
     420f == 875704422
     */
    
    var fliter420v: [AVCaptureDeviceFormat] {
        return filter { (format: AVCaptureDeviceFormat) -> Bool in
            return CMFormatDescriptionGetMediaSubType(format.formatDescription) == 875704438
        }
    }
    
    var sortedByQuality: [AVCaptureDeviceFormat] {
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
    
    var filterAspect4_3: [AVCaptureDeviceFormat] {
        return filter { (format: AVCaptureDeviceFormat) -> Bool in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return d.width * 3 == d.height * 4 || d.width * 4 == d.height * 3
        }
    }
    
    var filterAspect16_9: [AVCaptureDeviceFormat] {
        return filter { (format: AVCaptureDeviceFormat) -> Bool in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return d.width * 9 == d.height * 16 || d.width * 16 == d.height * 9
        }
    }
    
}
