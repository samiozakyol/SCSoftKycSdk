//
//  QKCutoutView.swift
//  QKMRZScanner
//
//  Created by Matej Dorcak on 05/10/2018.
//

import UIKit

class QKCutoutView: UIView {
    fileprivate(set) var cutoutRect: CGRect!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.45)
        contentMode = .redraw // Redraws everytime the bounds (orientation) changes
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        cutoutRect = calculateCutoutRect() // Orientation or the view's size could change
        layer.sublayers?.removeAll()
        drawRectangleCutout()
    }
    
    // MARK: Misc
    fileprivate func drawRectangleCutout() {
        let maskLayer = CAShapeLayer()
        let path = CGMutablePath()
        let cornerRadius = CGFloat(3)
        
        path.addRoundedRect(in: cutoutRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
        path.addRect(bounds)
        
        maskLayer.path = path
        maskLayer.fillRule = CAShapeLayerFillRule.evenOdd
        
        layer.mask = maskLayer
        
        // Add border around the cutout
        let borderLayer = CAShapeLayer()
        
        borderLayer.path = UIBezierPath(roundedRect: cutoutRect, cornerRadius: cornerRadius).cgPath
        borderLayer.lineWidth = 8
        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.frame = bounds
        
        layer.addSublayer(borderLayer)
    }
    
    fileprivate func calculateCutoutRect() -> CGRect {
        let documentFrameRatio = CGFloat(1.42) // Passport's size (ISO/IEC 7810 ID-3) is 125mm × 88mm
        let (width, height): (CGFloat, CGFloat)
        
        if bounds.height > bounds.width {
            width = (bounds.width * 0.9) // Fill 90% of the width
            height = (width / documentFrameRatio)
        }
        else {
            height = (bounds.height * 0.75) // Fill 75% of the height
            width = (height * documentFrameRatio)
        }
        
        let topOffset = (bounds.height - height) / 2
        let leftOffset = (bounds.width - width) / 2
        
        return CGRect(x: leftOffset, y: topOffset, width: width, height: height)
    }
}


/*class CornerRect: UIView {
    var color = UIColor.black {
        didSet {
            setNeedsDisplay()
        }
    }
    var radius: CGFloat = 5 {
        didSet {
            setNeedsDisplay()
        }
    }
    var thickness: CGFloat = 2 {
        didSet {
            setNeedsDisplay()
        }
    }
    var length: CGFloat = 30 {
        didSet {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        color.set()

        let t2 = thickness / 2
        let path = UIBezierPath()
        // Top left
        path.move(to: CGPoint(x: t2, y: length + radius + t2))
        path.addLine(to: CGPoint(x: t2, y: radius + t2))
        path.addArc(withCenter: CGPoint(x: radius + t2, y: radius + t2), radius: radius, startAngle: CGFloat.pi, endAngle: CGFloat.pi * 3 / 2, clockwise: true)
        path.addLine(to: CGPoint(x: length + radius + t2, y: t2))

        // Top right
        path.move(to: CGPoint(x: frame.width - t2, y: length + radius + t2))
        path.addLine(to: CGPoint(x: frame.width - t2, y: radius + t2))
        path.addArc(withCenter: CGPoint(x: frame.width - radius - t2, y: radius + t2), radius: radius, startAngle: 0, endAngle: CGFloat.pi * 3 / 2, clockwise: false)
        path.addLine(to: CGPoint(x: frame.width - length - radius - t2, y: t2))

        // Bottom left
        path.move(to: CGPoint(x: t2, y: frame.height - length - radius - t2))
        path.addLine(to: CGPoint(x: t2, y: frame.height - radius - t2))
        path.addArc(withCenter: CGPoint(x: radius + t2, y: frame.height - radius - t2), radius: radius, startAngle: CGFloat.pi, endAngle: CGFloat.pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: length + radius + t2, y: frame.height - t2))

        // Bottom right
        path.move(to: CGPoint(x: frame.width - t2, y: frame.height - length - radius - t2))
        path.addLine(to: CGPoint(x: frame.width - t2, y: frame.height - radius - t2))
        path.addArc(withCenter: CGPoint(x: frame.width - radius - t2, y: frame.height - radius - t2), radius: radius, startAngle: 0, endAngle: CGFloat.pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: frame.width - length - radius - t2, y: frame.height - t2))

        path.lineWidth = thickness
        path.stroke()
    }
}
*/
