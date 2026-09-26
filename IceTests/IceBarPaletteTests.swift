import CoreGraphics
import XCTest

final class IceBarPaletteTests: XCTestCase {
    private func image(_ rgba: [UInt8], width: Int = 1) -> CGImage {
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        return CGImage(width: width, height: rgba.count / 4 / width,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func testBlackAndWhiteChooseOppositeOpaqueBackground() {
        for (pixel, expected) in [([UInt8](arrayLiteral: 0, 0, 0, 255), IceBarPalette.light),
                                  ([255, 255, 255, 255], .dark)] {
            let tone = IceBarIconTone.analyze(image(pixel))!
            XCTAssertEqual(IceBarPalette.select([tone], fallback: .light), expected)
            XCTAssertEqual(expected.background.alpha, 1)
            XCTAssertFalse(tone.needsOutline(on: expected))
            XCTAssertTrue(tone.needsOutline(on: expected == .light ? .dark : .light))
        }
    }

    func testEachIconHasEqualVoteRegardlessOfSize() {
        let black = IceBarIconTone.analyze(image([0, 0, 0, 255]))!
        let white = IceBarIconTone.analyze(image(Array(repeating: [UInt8](arrayLiteral: 255, 255, 255, 255), count: 100).flatMap { $0 }, width: 100))!
        XCTAssertEqual(IceBarPalette.select([black, black, white], fallback: .dark), .light)
        XCTAssertEqual(IceBarPalette.select([black, white, white], fallback: .light), .dark)
        XCTAssertEqual(IceBarPalette.select([black, white], fallback: .dark), .dark)
    }

    func testTransparentAndEmptyUseSystemFallback() {
        XCTAssertNil(IceBarIconTone.analyze(image([0, 0, 0, 0])))
        for fallback in [IceBarPalette.light, .dark] {
            XCTAssertEqual(IceBarPalette.select([], fallback: fallback), fallback)
        }
    }

    func testPremultipliedWhiteAndTransparentPadding() {
        let tone = IceBarIconTone.analyze(image([128, 128, 128, 128, 0, 0, 0, 0], width: 2))!
        XCTAssertEqual(tone.luminance, 1, accuracy: 0.01)
        XCTAssertEqual(IceBarPalette.select([tone], fallback: .light), .dark)
        let black = IceBarIconTone.analyze(image([0, 0, 0, 128]))!
        XCTAssertEqual(IceBarPalette.select([black], fallback: .dark), .light)
    }

    func testColoredIconsKeepColorWithoutOutline() {
        let red = IceBarIconTone.analyze(image([255, 0, 0, 255]))!
        XCTAssertFalse(red.isMonochrome)
        XCTAssertFalse(red.needsOutline(on: .dark))
        XCTAssertEqual(IceBarPalette.select([red], fallback: .dark), .light)
        let yellow = IceBarIconTone.analyze(image([255, 255, 0, 255]))!
        XCTAssertEqual(IceBarPalette.select([yellow], fallback: .light), .dark)
    }
}
