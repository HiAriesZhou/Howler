import AppKit
import CoreText
import XCTest
@testable import Howler

@MainActor
final class LetteringTests: XCTestCase {
    func testInstalledFontLookupRetainsAvailableFontsAndRejectsSubstitution() {
        let available = "Helvetica"
        let found = Lettering.installedFont(available, size: 17)
        XCTAssertNotNil(found)
        if let found {
            XCTAssertEqual(CTFontCopyPostScriptName(found) as String, available)
            XCTAssertEqual(CTFontGetSize(found), 17)
        }
        XCTAssertNil(Lettering.installedFont("Howler-Unavailable-Fixture-Font", size: 17))
    }
}
