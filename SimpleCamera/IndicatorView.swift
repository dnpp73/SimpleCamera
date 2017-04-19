import UIKit

internal final class CircleIndicatorView: UIView {
    
    // for Focus
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
    
    override public func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return}
        let color = #colorLiteral(red: 0.9568627477, green: 0.8340871711, blue: 0.5, alpha: 1)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.0)
        ctx.addEllipse(in: rect.insetBy(dx: 4.0, dy: 4.0))
        ctx.strokePath()
    }
    
}

internal final class SquareIndicatorView: UIView {
    
    // for Exposure
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
    
    override public func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        let color = #colorLiteral(red: 0.9568627477, green: 0.8340871711, blue: 0.5, alpha: 1)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.0)
        ctx.addRect(rect.insetBy(dx: 1.0, dy: 1.0))
        ctx.strokePath()
        
        let margin: CGFloat = 1.0
        let length: CGFloat = 6.0
        // 上の縦線
        ctx.move(to: CGPoint(x: rect.midX, y: 0.0 + margin))
        ctx.addLine(to: CGPoint(x: rect.midX, y: 0.0 + margin + length))
        ctx.strokePath()
        
        // 右の横線
        ctx.move(to: CGPoint(x: rect.maxX - margin, y: rect.midY))
        ctx.addLine(to: CGPoint(x: rect.maxX - margin - length, y: rect.midY))
        ctx.strokePath()
        
        // 下の縦線
        ctx.move(to: CGPoint(x: rect.midX, y: rect.maxY - margin))
        ctx.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - margin - length))
        ctx.strokePath()
        
        // 左の横線
        ctx.move(to: CGPoint(x: 0.0 + margin, y: rect.midY))
        ctx.addLine(to: CGPoint(x: 0.0 + margin + length, y: rect.midY))
        ctx.strokePath()
    }
    
}
