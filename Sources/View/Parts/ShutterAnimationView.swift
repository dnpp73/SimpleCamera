#if canImport(UIKit)

import UIKit

internal final class ShutterAnimationView: UIView {

    internal func shutterCloseAnimation(duration: TimeInterval, completion: ((Bool) -> Void)?) {
        let anim = {
            self.backgroundColor = UIColor.black
        }
        let comp = { (finished: Bool) -> Void in
            completion?(finished)
        }
        if duration > 0.0 {
            UIView.animate(withDuration: duration, animations: anim, completion: comp)
        } else {
            anim()
            comp(true)
        }
    }

    internal func shutterOpenAnimation(duration: TimeInterval, completion: ((Bool) -> Void)?) {
        let anim = {
            self.backgroundColor = UIColor.clear
        }
        let comp = { (finished: Bool) -> Void in
            completion?(finished)
        }
        if duration > 0.0 {
            UIView.animate(withDuration: duration, animations: anim, completion: comp)
        } else {
            anim()
            comp(true)
        }
    }

}

#endif
