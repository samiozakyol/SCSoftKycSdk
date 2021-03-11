import UIKit

class OvalOverlayView: UIView {
    
    //let screenBounds = UIScreen.main.bounds
    var overlayFrame: CGRect!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        //backgroundColor = UIColor.clear
        backgroundColor = UIColor.black.withAlphaComponent(0.45)
        contentMode = .redraw
        //accessibilityIdentifier = "takeASelfieOvalOverlayView"
    }
    
    fileprivate func calculateCutoutRect() -> CGRect {
        return CGRect(x: (bounds.width - 300.0) / 2,
                      y: (bounds.height - 400.0) / 2,
                      width: 300.0,
                      height: 400.0)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        overlayFrame = calculateCutoutRect()
        layer.sublayers?.removeAll()
        drawOvalCutout()
    }
    
    fileprivate func drawOvalCutout() {
        let maskLayer = CAShapeLayer()
        let path = CGMutablePath()
        
        path.addEllipse(in: overlayFrame)
        path.addRect(bounds)

        maskLayer.path = path
        maskLayer.fillRule = CAShapeLayerFillRule.evenOdd

        layer.mask = maskLayer
        
        //let overlayPath = UIBezierPath(rect: bounds)
        //overlayPath.append(ovalPath)
        //overlayPath.usesEvenOddFillRule = true
        // draw oval layer
        let ovalLayer = CAShapeLayer()
        ovalLayer.path =  UIBezierPath(ovalIn: overlayFrame).cgPath
        ovalLayer.fillColor = UIColor.clear.cgColor
        ovalLayer.strokeColor = UIColor.white.cgColor
        ovalLayer.lineWidth = 8
        ovalLayer.frame = bounds
        // draw layer that fills the view
        //let fillLayer = CAShapeLayer()
        //fillLayer.path = overlayPath.cgPath
        //fillLayer.fillRule = CAShapeLayerFillRule.evenOdd
        //fillLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        // add layers
        //layer.addSublayer(fillLayer)
        layer.addSublayer(ovalLayer)
    }
    
}
