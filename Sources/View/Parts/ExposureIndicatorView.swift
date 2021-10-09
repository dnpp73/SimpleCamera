import UIKit

internal final class ExposureIndicatorView: UIView {

    @IBOutlet private weak var indicatorView: UIView! // Square

    private let baseAlpha: CGFloat = 0.8
    private let movingTime: TimeInterval = 0.25
    private let fadeTime: TimeInterval = 0.3
    private let afterDelay: TimeInterval = 2.0
    private var resetBounds: CGRect {
        let shortSide = min(bounds.width, bounds.height) / 3.0 * 0.85
        return CGRect(x: 0.0, y: 0.0, width: shortSide, height: shortSide)
    }
    private var exposureBounds: CGRect {
        let shortSide = min(bounds.width, bounds.height) / 3.0 * 0.7
        return CGRect(x: 0.0, y: 0.0, width: shortSide, height: shortSide)
    }

    internal func exposureResetAnimation(animated: Bool = true) {
        let selector = #selector(animateIndicatorViewAlpha)
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: selector, object: nil)
        UIView.animate(withDuration: animated ? movingTime : 0.0, delay: 0.0, options: [.beginFromCurrentState, .curveEaseInOut], animations: {
            self.indicatorView.alpha = self.baseAlpha
            self.indicatorView.center = self.center
            self.indicatorView.bounds = self.resetBounds
        }, completion: { (finished: Bool) -> Void in
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: selector, object: nil)
            self.perform(selector, with: nil, afterDelay: self.afterDelay)
        })
    }

    internal func exposureAnimation(to point: CGPoint) {
        let selector = #selector(animateIndicatorViewAlpha)
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: selector, object: nil)
        UIView.animate(withDuration: movingTime, delay: 0.0, options: [.beginFromCurrentState, .curveEaseInOut], animations: {
            self.indicatorView.alpha = self.baseAlpha
            self.indicatorView.center = point
            self.indicatorView.bounds = self.exposureBounds
        }, completion: { (finished: Bool) -> Void in
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: selector, object: nil)
            self.perform(selector, with: nil, afterDelay: self.afterDelay)
        })
    }

    @objc
    private func animateIndicatorViewAlpha() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #function, object: nil)
        let alpha: CGFloat = indicatorView.center == center ? 0.0 : baseAlpha / 2.0
        UIView.animate(withDuration: fadeTime, delay: 0.0, options: [.beginFromCurrentState, .curveEaseInOut], animations: {
            self.indicatorView.alpha = alpha
        }, completion: { (finished: Bool) -> Void in
            // nop
        })
    }

}
