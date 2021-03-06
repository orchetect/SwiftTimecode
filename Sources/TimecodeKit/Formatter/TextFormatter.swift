//
//  TextFormatter.swift
//  TimecodeKit
//
//  Created by Steffan Andrews on 2020-07-11.
//  Copyright © 2020 Steffan Andrews. All rights reserved.
//

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#else
import Foundation
#endif

// MARK: - TextFormatter

extension Timecode {
	
	/// Formatter subclass
	/// (Used in Timecode.TextField)
	@objc(TimecodeTextFormatter)
	public class TextFormatter: Formatter {
		
		// MARK: properties
		
		public var frameRate: Timecode.FrameRate?
		public var upperLimit: Timecode.UpperLimit?
		public var displaySubFrames: Bool?
		public var subFramesDivisor: Int?
		
		/// The formatter's `attributedString(...) -> NSAttributedString` output will override a control's alignment (ie: `NSTextField`).
		/// Setting alignment here will add the appropriate paragraph alignment attribute to the output `NSAttributedString`.
		public var alignment: NSTextAlignment = .natural
		
		/// When set true, invalid timecode component values are individually attributed.
		public var showsValidation: Bool = false
		
		/// The `NSAttributedString` attributes applied to invalid values if `showsValidation` is set.
		///
		/// Defaults to red foreground color.
		
		public var validationAttributes: [NSAttributedString.Key : Any]
			= {
				#if os(macOS)
				return [.foregroundColor: NSColor.red]
				#elseif os(iOS) || os(tvOS) || os(watchOS)
				return [.foregroundColor: UIColor.red]
				#else
				return []
				#endif
			}()
		
		
		// MARK: init
		
		public required init?(coder: NSCoder) {
			
			super.init(coder: coder)
			
		}
		
		public init(frameRate: Timecode.FrameRate? = nil,
					limit: Timecode.UpperLimit? = nil,
					displaySubFrames: Bool? = nil,
					subFramesDivisor: Int? = nil,
					showsValidation: Bool = false,
					validationAttributes: [NSAttributedString.Key: Any]? = nil) {
			
			super.init()
			
			self.frameRate = frameRate
			self.upperLimit = limit
			self.subFramesDivisor = subFramesDivisor
			self.displaySubFrames = displaySubFrames

			self.showsValidation = showsValidation
			
			if let validationAttributes = validationAttributes {
				self.validationAttributes = validationAttributes
			}
			
		}
		
		/// Initializes with properties from an `Timecode` object.
		public convenience init(using timecode: Timecode,
								showsValidation: Bool = false,
								validationAttributes: [NSAttributedString.Key: Any]? = nil) {
			
			self.init(frameRate: timecode.frameRate,
					  limit: timecode.upperLimit,
					  displaySubFrames: timecode.displaySubFrames,
					  subFramesDivisor: timecode.subFramesDivisor,
					  showsValidation: showsValidation,
					  validationAttributes: validationAttributes)
			
		}
		
		public func inheritProperties(from other: Timecode.TextFormatter) {
			self.frameRate = other.frameRate
			self.upperLimit = other.upperLimit
			self.subFramesDivisor = other.subFramesDivisor
			self.displaySubFrames = other.displaySubFrames
			
			self.alignment = other.alignment
			self.showsValidation = other.showsValidation
			self.validationAttributes = other.validationAttributes
		}
		
		// MARK: - Override methods
		
		// MARK: string

		override public func string(for obj: Any?) -> String? {
			
			guard let string = obj as? String
			else { return nil }
			
			guard var tc = timecodeTemplate
			else { return string }

			// form timecode components without validating
			guard let tcc = Timecode.decode(timecode: string)
			else { return string }
			
			// set values without validating
			tc.setTimecode(rawValues: tcc)
			
			return tc.stringValue
			
		}
		
		// MARK: attributedString

		override public func attributedString(for obj: Any,
											  withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
			
			guard let string = string(for: obj)
			else { return nil }

			func entirelyInvalid() -> NSAttributedString {
				self.showsValidation
					? NSAttributedString(string: string,
										 attributes: self
											.validationAttributes
											.merging(attrs ?? [:],
													 uniquingKeysWith: { current, _ in current })
					)
					.addingAttribute(alignment: self.alignment)
					: NSAttributedString(string: string, attributes: attrs)
					.addingAttribute(alignment: self.alignment)
			}

			// grab properties from the formatter
			guard var tc = timecodeTemplate else { return entirelyInvalid() }

			// form timecode components without validating
			guard let tcc = Timecode.decode(timecode: string) else { return entirelyInvalid() }

			// set values without validating
			tc.setTimecode(rawValues: tcc)

			return
				(
					self.showsValidation
						? tc.stringValueValidated(invalidAttributes: self.validationAttributes,
												  withDefaultAttributes: attrs)
						: NSAttributedString(string: string, attributes: attrs)
				)
				.addingAttribute(alignment: self.alignment)
			
		}

		override public func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
											for string: String,
											errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
			
			obj?.pointee = string as NSString
			return true
			
		}

		// MARK: isPartialStringValid

		override public func isPartialStringValid(_ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
												  proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
												  originalString origString: String,
												  originalSelectedRange origSelRange: NSRange,
												  errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
			
			guard let frameRate = frameRate,
				  let limit = upperLimit,
				  //let subFramesDivisor = subFramesDivisor,
				  let displaySubFrames = displaySubFrames else { return true }

			let partialString = partialStringPtr.pointee as String
			
			// baseline checks
			
			if partialString.isEmpty { return true } // allow empty field
			// if partialString.count > 20 { return false }	// don't allow too many chars
			
			// constants
			
			let numberChars = CharacterSet(charactersIn: "0123456789")
			// let coreSeparatorChars = CharacterSet(charactersIn: ":;")
			// let allSeparatorChars = CharacterSet(charactersIn: ":;. ")
			
			let allowedChars = CharacterSet(charactersIn: "0123456789:;. ")
			let disallowedChars = allowedChars.inverted
			
			// more baseline checks
			
			if let _ = partialString.rangeOfCharacter(from: disallowedChars,
													  options: .caseInsensitive) {
				error?.pointee = NSString("Invalid characters.")
				return false
			}
			
			// parse
			
			var string = ""
			var fixed = false
			var consecutiveIntCount = 0
			var intGrouping = 0
			var spaceCount = 0
			var colonCount = 0
			var periodCount = 0
			var lastChar: Character?
			
			for var char in partialString {
				
				// prep
				
				if numberChars.contains(char) {
					consecutiveIntCount += 1
				}

				// separators
				
				switch char {
				case ".":
					if colonCount < 3 {
						char = frameRate.isDrop && (colonCount == 2)
							? ";" : ":"
						
						fixed = true
					}
					else if periodCount == 0 { break }
					else { return false }
					
				case ";":
					if colonCount < 3 {
						char = frameRate.isDrop && (colonCount == 2)
							? ";" : ":"
						
						fixed = true
					}
					
				default: break
				}
				
				if char == " " {
					if limit == ._24hours
					{ return false }
					
					if !(intGrouping == 1
							&& spaceCount == 0
							&& colonCount == 0
							&& periodCount == 0)
					{ return false }
					
					spaceCount += 1
				}
				
				// separator validation
				
				if char == ":" || char == ";"
				{ colonCount += 1; consecutiveIntCount = 0 }
				
				if (char == ":" || char == ";") && colonCount >= 4
				{ return false }
				
				// period validation
				
				if char == "."
				{ periodCount += 1 }
				
				if char == "." && periodCount > 1
				{ return false }
				
				if char == "." && !displaySubFrames
				{ return false }
				
				// number validation (?)
				
				// cleanup
				
				if numberChars.contains(char) {
					if let unwrappedLastChar = lastChar {
						if !numberChars.contains(unwrappedLastChar)
						{ intGrouping += 1 }
					} else {
						intGrouping += 1
					}
				}

				// cycle variables
				
				lastChar = char

				// append char
				
				string += "\(char)"
			}

			if fixed {
				partialStringPtr.pointee = NSString(string: string)
				return false
			} else {
				return true
			}
			
		}
		
	}
	
}

// MARK: timecodeTemplate

extension Timecode.TextFormatter {
	
    @available(swift, obsoleted: 0.1, renamed: "timecodeTemplate")
    public var timecodeWithProperties: Timecode? {
        timecodeTemplate
    }
    
	public var timecodeTemplate: Timecode? {
		
		guard let frameRate = frameRate,
			  let upperLimit = upperLimit,
			  let subFramesDivisor = subFramesDivisor,
			  let displaySubFrames = displaySubFrames else {
			
			return nil
			
		}
        
        return Timecode(at: frameRate,
                        limit: upperLimit,
                        subFramesDivisor: subFramesDivisor,
                        displaySubFrames: displaySubFrames)
        
    }
    
}
