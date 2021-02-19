//
//  ToggleButton.swift
//  VisionCreditScan
//
//  Created by work on 14.01.2021.
//  Copyright © 2021 iowncode. All rights reserved.
//

import UIKit
class ToggleButton: UIButton {
    
    /*@IBInspectable var highlightedSelectedImage:UIImage?
    
    override func awakeFromNib() {
        self.addTarget(self, action: #selector(btnClicked(_:)),
                       for: .touchUpInside)
        self.setImage(highlightedSelectedImage,
                      for: [.highlighted, .selected])
    }
    
    @objc func btnClicked (_ sender:UIButton) {
        isSelected.toggle()
    }*/
    
    @IBInspectable  var isOn:Bool = false{
        didSet{
            updateDisplay()
        }
    }
    
    @IBInspectable var onImage:UIImage! = nil{
        didSet{
            updateDisplay()
        }
    }
    
    @IBInspectable var offImage:UIImage! = nil{
        didSet{
            updateDisplay()
        }
    }
     
    func updateDisplay(){
        if isOn {
            if let onImage = onImage{
                setBackgroundImage(onImage, for: .normal)
            }
        } else {
            if let offImage = offImage{
                setBackgroundImage(offImage, for: .normal)
            }
        }
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        isOn = !isOn
    }
    
}
