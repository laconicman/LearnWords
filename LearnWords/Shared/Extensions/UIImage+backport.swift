//
//  UIImage+backport.swift
//  LearnWords
//
//  Created by Paul Buktab on 4/27/25.
//  Copyright © 2025 Paul. All rights reserved.
//
import UIKit

extension UIImage {
    static func systemImage(_ names: [String] /*, bundle: Bundle? = nil, renderMode: UIImage.RenderingMode = .automatic */) -> UIImage? {
        if #available(iOS 13, *) {
            names.lazy.compactMap({ UIImage(systemName: $0) }).first
        } else {
            // TODO: look up in assets
            nil
        }
    }
    
    static func systemImage(_ name: String /*, bundle: Bundle? = nil, renderMode: UIImage.RenderingMode = .automatic */) -> UIImage? {
        systemImage([name])
    }
}
