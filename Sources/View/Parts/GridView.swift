import UIKit

public final class GridView: UIView {

    // MARK: - Grid Setting

    public var gridType: GridType = .none {
        didSet {
            setNeedsDisplay()
        }
    }

    @IBInspectable public var blackLineWidth: CGFloat = 1.0 {
        didSet {
            setNeedsDisplay()
        }
    }

    @IBInspectable public var whiteLineWidth: CGFloat = 0.5 {
        didSet {
            setNeedsDisplay()
        }
    }

    @IBInspectable public var blackLineAlpha: CGFloat = 0.7 {
        didSet {
            setNeedsDisplay()
        }
    }

    @IBInspectable public var whiteLineAlpha: CGFloat = 1.0 {
        didSet {
            setNeedsDisplay()
        }
    }

    // MARK: - UIView

    override public func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override public func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else {
            return
        }

        switch gridType {
        case .none:
            break
        case .equalDistance(let vertical, let horizontal):
            ctx.setLineWidth(blackLineWidth + whiteLineWidth)
            ctx.setStrokeColor(gray: 0.0, alpha: blackLineAlpha) // 黒
            for i in 0..<vertical {
                // 縦の黒線
                let n = CGFloat(i + 1) * rect.width / CGFloat(vertical + 1)
                ctx.move(to: CGPoint(x: n, y: 0.0))
                ctx.addLine(to: CGPoint(x: n, y: rect.height))
                ctx.strokePath()
            }
            for i in 0..<horizontal {
                // 横の黒線
                let n = CGFloat(i + 1) * rect.height / CGFloat(horizontal + 1)
                ctx.move(to: CGPoint(x: 0.0, y: n))
                ctx.addLine(to: CGPoint(x: rect.width, y: n))
                ctx.strokePath()
            }

            ctx.setLineWidth(whiteLineWidth)
            ctx.setStrokeColor(gray: 1.0, alpha: whiteLineAlpha) // 白
            for i in 0..<vertical {
                // 縦の白線
                let n = CGFloat(i + 1) * rect.width / CGFloat(vertical + 1)
                ctx.move(to: CGPoint(x: n, y: 0.0))
                ctx.addLine(to: CGPoint(x: n, y: rect.height))
                ctx.strokePath()
            }
            for i in 0..<horizontal {
                // 横の白線
                let n = CGFloat(i + 1) * rect.height / CGFloat(horizontal + 1)
                ctx.move(to: CGPoint(x: 0.0, y: n))
                ctx.addLine(to: CGPoint(x: rect.width, y: n))
                ctx.strokePath()
            }
        }

    }

}
