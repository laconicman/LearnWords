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
    
    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
//        (layer as! CAGradientLayer).startPoint = CGPoint(x: 0, y: 0)
//        (layer as! CAGradientLayer).endPoint = CGPoint(x: 1, y: 1)
//        (layer as! CAGradientLayer).locations = [0,1]
        
        //Controll round corners here!
        (layer as! CAGradientLayer).colors = [startColor.cgColor, endColor.cgColor]
    }
    
}
