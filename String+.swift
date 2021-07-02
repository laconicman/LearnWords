//
//  String+.swift
//  LearnWords
//
//  Created by Paul on 05/10/2019.
//  Copyright © 2019 Paul. All rights reserved.
//

// import Foundation
import UIKit

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

extension String {
    private var regexMatchWords: NSRegularExpression? { try? NSRegularExpression(pattern: "\\w+") }
    var aproxWordCount: Int {
        guard let regex = regexMatchWords else { return 0 }
        return regex.numberOfMatches(in: self, range: NSRange(self.startIndex..., in: self))
    }
}

// TODO: Those are ugly
extension String {
    /// Not a totally correct
    func fullRange1() -> NSRange {
        return NSMakeRange(0, self.count)
    }
    /* Deprecated
    func fullNSRange() -> NSRange {
        return NSRange(self.startIndex.encodedOffset ..< self.endIndex.encodedOffset)
    } */
}

extension String {
    func fullRange2() -> Range<String.Index> {
        return Range(uncheckedBounds: (lower: self.startIndex, upper: self.endIndex))
    }
    //Stays here as a riminder
//    func fullNSRangeBad() -> NSRange {
//        return NSRange(self) ?? NSRange(location: 0, length: 0)
//    }
    func fullNSRange() -> NSRange {
      NSRange(location: 0, length: self.utf16.count)
    }
    /* Deprecated
    func fullRange7() -> NSRange {
        return NSRange(self.startIndex.encodedOffset ..< self.endIndex.encodedOffset)
    } */
    func nsRange(of substring: String) -> NSRange? {
        if let rangeOfSubstring = self.range(of: substring) {
            return NSRange(rangeOfSubstring, in: self)
        } else {
           return nil
        }
    }
}

extension String {
    var fullRange3: Range<String.Index> { return startIndex..<endIndex }
}
// Usage
//let swiftRange = "abc".fullRange
//or
//let nsRange = "abc".fullRange.toRange

//And when you need NSRange from String in Swift 4:
//NSRange(string.startIndex.encodedOffset ..< string.endIndex.encodedOffset)

// Deprecated
//extension NSRange {
//    public init(_ range: Range<String.Index>) {
//        self.init(location: range.lowerBound.encodedOffset, length: range.upperBound.encodedOffset - range.lowerBound.encodedOffset)
//    }
//}
//
//extension Range where Bound == String.Index {
//    var nsRange: NSRange {
//        return NSRange(location: self.lowerBound.encodedOffset, length: self.upperBound.encodedOffset - self.lowerBound.encodedOffset)
//    }
//}


func isReal(word: String) -> Bool {
    let checker = UITextChecker()
    let range = NSRange(location: 0, length: word.utf16.count)
    // guard let range = NSRange(word) else { return false }
    // TODO: set language from settings
    let misspelledRange = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: "en")
    return misspelledRange.location == NSNotFound
}

extension String {
    func canonicalise() -> String
    {
        self.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
