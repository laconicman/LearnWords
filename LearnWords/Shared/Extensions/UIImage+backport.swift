//
//  UIImage+backport.swift
//  LearnWords
//
//  Created by Paul Buktab on 4/27/25.
//  Copyright © 2025 Paul. All rights reserved.
//
import UIKit

extension UIImage {
    /// The first of `names` the running OS has as an SF Symbol, or `nil` if it has none.
    /// No longer a backport, and not dead because of that: a preferred name listed before a
    /// fallback is how an icon whose symbol some OS versions lack still draws something.
    static func systemImage(_ names: [String] /*, bundle: Bundle? = nil, renderMode: UIImage.RenderingMode = .automatic */) -> UIImage? {
        names.lazy.compactMap({ UIImage(systemName: $0) }).first
    }
    
    static func systemImage(_ name: String /*, bundle: Bundle? = nil, renderMode: UIImage.RenderingMode = .automatic */) -> UIImage? {
        systemImage([name])
    }
}
