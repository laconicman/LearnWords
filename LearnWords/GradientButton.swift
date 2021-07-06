//
//  GradientButton.swift
//  LearnWords
//
//  Created by Paul on 10.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//

import UIKit
@IBDesignable class GradientButton: UIButton {
    @IBInspectable var startColor: UIColor = UIColor.white
    @IBInspectable var endColor: UIColor = UIColor.white
    @IBInspectable var cornerRadius = CGFloat(5.0)
    
    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        //This is an advanced gradient we do not use for now
//        (layer as! CAGradientLayer).startPoint = CGPoint(x: 0, y: 0)
//        (layer as! CAGradientLayer).endPoint = CGPoint(x: 1, y: 1)
//        (layer as! CAGradientLayer).locations = [0,1]
        
        // Simple gradient
        (layer as! CAGradientLayer).colors = [startColor.cgColor, endColor.cgColor]
        
        //Controll round corners and border here. TODO: make them inspectable?
        layer.cornerRadius = cornerRadius
        layer.borderWidth = 1
        layer.borderColor = UIColor.lightGray.cgColor
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.2
    }
    
}
