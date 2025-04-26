//
//  UIContextualAction+ConvenienceInit.swift
//  LearnWords
//
//  Created by Paul Buktab on 4/26/25.
//  Copyright © 2025 Paul. All rights reserved.
//

import UIKit.UIContextualAction

extension UIContextualAction {

    @available(iOS 11.0, *)
    public convenience init(style: UIContextualAction.Style, title: String?, backgroundColor: UIColor?, image: UIImage? = nil, handler: @escaping UIContextualAction.Handler) {
        self.init(style: style, title: title, handler: handler)
        self.image = image
        self.backgroundColor = backgroundColor
    }

}
