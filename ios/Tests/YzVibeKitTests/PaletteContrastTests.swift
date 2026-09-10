import XCTest
import SwiftUI
import UIKit
@testable import YzVibeKit

/// 色板的无障碍回归：任何一次改色都必须仍然满足 WCAG AA。
///
/// 上一版设计里，主按钮的白字只有 3.50:1、时间戳只有 2.69:1，是靠人工核对才发现的。
/// 这些断言把「改颜色」和「掉到不合规」绑在一起，改坏了会直接红。
final class PaletteContrastTests: XCTestCase {

    /// WCAG 相对亮度。
    private func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func ratio(_ fg: Color, on bg: Color) -> Double {
        let a = luminance(fg), b = luminance(bg)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func assertContrast(_ fg: Color, on bg: Color, atLeast target: Double,
                                _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let r = ratio(fg, on: bg)
        XCTAssertGreaterThanOrEqual(
            r, target,
            String(format: "%@ 只有 %.2f:1，低于要求的 %.1f:1", what, r, target),
            file: file, line: line
        )
    }

    private func check(_ p: Palette, _ name: String) {
        // 正文与按钮文字：AA 要求 4.5:1
        assertContrast(p.brandInk, on: p.brand, atLeast: 4.5, "\(name) 主按钮文字")
        assertContrast(p.label, on: p.surface, atLeast: 7, "\(name) 主文字 / 页面底")
        assertContrast(p.label, on: p.surfaceElevated, atLeast: 7, "\(name) 主文字 / 卡片")
        assertContrast(p.labelSecondary, on: p.surface, atLeast: 4.5, "\(name) 副文字")
        assertContrast(p.labelSecondary, on: p.fill, atLeast: 4.5, "\(name) 副文字 / fill")
        // 胶囊：深色文字压在同色系浅底上
        assertContrast(p.brandText, on: p.brandSoft, atLeast: 4.5, "\(name) 品牌胶囊文字")
        assertContrast(p.sage, on: p.sageSoft, atLeast: 4.5, "\(name) 绿色胶囊文字")
        assertContrast(p.danger, on: p.dangerSoft, atLeast: 4.5, "\(name) 危险胶囊文字")
        assertContrast(p.amberText, on: p.amberSoft, atLeast: 4.5, "\(name) 琥珀胶囊文字")
        // 强调色当正文用（链接、状态文字）
        assertContrast(p.brandText, on: p.surface, atLeast: 4.5, "\(name) 品牌文字 / 页面底")
        assertContrast(p.danger, on: p.surface, atLeast: 4.5, "\(name) 危险文字 / 页面底")
        // 非文本元素（状态点、色条、图标）：AA 要求 3:1
        assertContrast(p.brand, on: p.surface, atLeast: 3, "\(name) 品牌色块 / 页面底")
        assertContrast(p.sage, on: p.surface, atLeast: 3, "\(name) 在线状态点")
        assertContrast(p.amber, on: p.surface, atLeast: 3, "\(name) 警示色条")
        assertContrast(p.labelTertiary, on: p.surface, atLeast: 3, "\(name) 三级文字 / 时间戳")
    }

    func testLightPaletteMeetsAA() { check(.light, "浅色") }
    func testDarkPaletteMeetsAA() { check(.dark, "深色") }
    func testLightHighContrastPaletteMeetsAA() { check(.lightHighContrast, "浅色增强对比") }
    func testDarkHighContrastPaletteMeetsAA() { check(.darkHighContrast, "深色增强对比") }

    /// 「增强对比度」必须真的更强，否则那个开关等于没接。
    func testHighContrastIsActuallyStronger() {
        XCTAssertGreaterThan(ratio(Palette.lightHighContrast.labelTertiary, on: Palette.lightHighContrast.surface),
                             ratio(Palette.light.labelTertiary, on: Palette.light.surface))
        XCTAssertGreaterThan(ratio(Palette.darkHighContrast.labelTertiary, on: Palette.darkHighContrast.surface),
                             ratio(Palette.dark.labelTertiary, on: Palette.dark.surface))
    }

    /// 色板按「深色模式 + 增强对比度」正确取用。
    func testPaletteSelection() {
        XCTAssertEqual(luminance(Palette.current(.dark).surface), luminance(Palette.dark.surface), accuracy: 0.0001)
        XCTAssertEqual(luminance(Palette.current(.light).surface), luminance(Palette.light.surface), accuracy: 0.0001)
        XCTAssertEqual(luminance(Palette.current(.dark, .increased).surface), luminance(Palette.darkHighContrast.surface), accuracy: 0.0001)
        XCTAssertEqual(luminance(Palette.current(.light, .increased).surface), luminance(Palette.lightHighContrast.surface), accuracy: 0.0001)
    }
}
