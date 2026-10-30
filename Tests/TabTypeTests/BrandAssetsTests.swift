import AppKit
import XCTest
@testable import TabType

@MainActor
final class BrandAssetsTests: XCTestCase {
    func testMenuBarLoadsBundledTemplateAtNativeSize() throws {
        let image = try XCTUnwrap(BrandAssets.menuBarIcon())
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(image.representations.map(\.pixelsWide).sorted(), [18, 36])
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertTrue(bitmap.hasAlpha)
    }

    func testAppBrandArtworkLoadsFromTheSameResourceBundle() throws {
        let image = try XCTUnwrap(BrandAssets.appIcon())
        XCTAssertGreaterThanOrEqual(image.size.width, 512)
        XCTAssertGreaterThanOrEqual(image.size.height, 512)
    }
}
