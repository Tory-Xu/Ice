//
//  IceBarPalette.swift
//  Ice
//

import Foundation
import CoreGraphics

/// Pixel analysis shared by the image cache and the Ice Bar. Never samples wallpaper.
enum IceBarPalette: Equatable {
    case light, dark

    var background: CGColor {
        let value: CGFloat = self == .light ? 242.0 / 255 : 36.0 / 255
        return CGColor(srgbRed: value, green: value, blue: value, alpha: 1)
    }

    static func select(_ icons: [IceBarIconTone], fallback: IceBarPalette) -> IceBarPalette {
        let darkCount = icons.filter { $0.luminance < 0.5 }.count
        let lightCount = icons.count - darkCount
        if darkCount == lightCount { return fallback }
        return darkCount > lightCount ? .light : .dark
    }
}

struct IceBarIconTone {
    let luminance: Double
    let isMonochrome: Bool

    func needsOutline(on palette: IceBarPalette) -> Bool {
        guard isMonochrome else { return false }
        let background = palette == .light ? Self.linear(242.0 / 255) : Self.linear(36.0 / 255)
        return (max(luminance, background) + 0.05) / (min(luminance, background) + 0.05) < 3
    }

    private static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func analyze(_ image: CGImage) -> IceBarIconTone? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var weight = 0.0
        var luminance = 0.0
        var coloredWeight = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0 else { continue }
            // Decode premultiplied channels before measuring brightness/saturation.
            let r = min(1, Double(pixels[offset]) / 255 / alpha)
            let g = min(1, Double(pixels[offset + 1]) / 255 / alpha)
            let b = min(1, Double(pixels[offset + 2]) / 255 / alpha)
            luminance += (0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)) * alpha
            weight += alpha
            if max(r, g, b) - min(r, g, b) > 0.1 { coloredWeight += alpha }
        }
        guard weight > 0 else { return nil }
        return IceBarIconTone(luminance: luminance / weight, isMonochrome: coloredWeight / weight < 0.05)
    }
}
