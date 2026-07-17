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
    

    
    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.2
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.2
        //fatalError("init(coder:) has not been implemented")
    }
    
//        override func layoutSubviews() {
//            super.layoutSubviews()
//            gradientLayer.frame = bounds
//        }
    
//    private lazy var gradientLayer: CAGradientLayer = {
//        let l = CAGradientLayer()
//        l.frame = self.bounds
//        l.colors = [startColor.cgColor, endColor.cgColor]
////        l.startPoint = CGPoint(x: 0, y: 0.5)
////        l.endPoint = CGPoint(x: 1, y: 0.5)
//        l.cornerRadius = cornerRadius
//        l.borderWidth = 1
//        l.borderColor = UIColor.lightGray.cgColor
//        layer.insertSublayer(l, at: 0)
//        return l
//    }()
    
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
        // titleLabel?.adjustsFontSizeToFitWidth = true
        // titleLabel?.minimumScaleFactor = 0.2
    }
    
}
