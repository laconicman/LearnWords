//
//  String+.swift
//  LearnWords
//
//  Created by Paul on 05/10/2019.
//  Copyright © 2019 Paul. All rights reserved.
//

// import Foundation

extension String {
    static func emojiFlag(for countryCode: String) -> String? {
        func isLowercaseASCIIEnglishLetterScalar(_ scalar: Unicode.Scalar) -> Bool {
            // return scalar.value >= 0x61 && scalar.value <= 0x7A
            // The same but more human readable
            return scalar.value >= Unicode.Scalar("a").value && scalar.value <= Unicode.Scalar("z").value
            // The same but in term of scalar properties
            // return scalar.isASCII && scalar.properties.isLowercase && scalar.isLetter
        }
        
        func regionalIndicatorSymbol(for scalar: Unicode.Scalar) -> Unicode.Scalar {
            precondition(isLowercaseASCIIEnglishLetterScalar(scalar))
            
            // 0x1F1E6 marks the start of the Regional Indicator Symbol range and corresponds to 'A'
            // 0x61 marks the start of the lowercase ASCII alphabet: 'a'
            return Unicode.Scalar(scalar.value + (0x1F1E6 - 0x61))!
        }
        
        let lowercasedCode = countryCode.lowercased()
        guard lowercasedCode.count == 2 else { return nil }
        // guard lowercasedCode.unicodeScalars.reduce(true, { accum, scalar in accum && isLowercaseASCIIScalar(scalar) }) else { return nil }
        
        guard lowercasedCode.unicodeScalars.allSatisfy(isLowercaseASCIIEnglishLetterScalar) else {return nil }
        
        let indicatorSymbols = lowercasedCode.unicodeScalars.map({ regionalIndicatorSymbol(for: $0) })
        return String(indicatorSymbols.map({ Character($0) }))
    }
}
