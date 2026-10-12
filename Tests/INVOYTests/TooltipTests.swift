import XCTest
import AppKit
@testable import INVOY

final class TooltipTests: XCTestCase {
    @MainActor func testTooltipEscapesClippedContentAndDoesNotInterceptClicks() throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 270, y: 240, width: 40, height: 40))
        window.contentView?.addSubview(anchor)
        let presenter = TooltipPresenter.shared
        defer { presenter.hide(); window.orderOut(nil) }
        presenter.show("Pridať úhradu", at: anchor)
        let panel = try XCTUnwrap(presenter.panel)
        let target = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        XCTAssertEqual(panel.parent, window)
        XCTAssertEqual(panel.frame.midX, target.midX, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, target.minY - 8, accuracy: 1)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertGreaterThan(panel.frame.width, 60)
        let bubble = try XCTUnwrap(panel.contentView)
        let bitmap = try XCTUnwrap(bubble.bitmapImageRepForCachingDisplay(in: bubble.bounds))
        bubble.cacheDisplay(in: bubble.bounds, to: bitmap)
        var whitePixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.alphaComponent > 0.9, color.redComponent > 0.9,
                   color.greenComponent > 0.9, color.blueComponent > 0.9 { whitePixels += 1 }
            }
        }
        XCTAssertGreaterThan(whitePixels, 20, "Tooltip text must render visibly on its dark background")
        presenter.hide(for: NSView())
        XCTAssertNotNil(presenter.panel, "Leaving another control must not close the current tooltip")
        presenter.hide(for: anchor)
        XCTAssertNil(presenter.panel)
        XCTAssertFalse(window.childWindows?.contains(panel) ?? false)
    }

    @MainActor func testLongTooltipStaysInsideScreenAndReplacingItClosesOldPanel() throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let window = NSWindow(contentRect: NSRect(x: screen.maxX - 100, y: screen.midY, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 60, y: 40, width: 40, height: 40))
        window.contentView?.addSubview(anchor)
        let presenter = TooltipPresenter.shared
        defer { presenter.hide(); window.orderOut(nil) }
        presenter.show("Odstrániť bankový účet s dlhším názvom", at: anchor)
        let old = try XCTUnwrap(presenter.panel)
        XCTAssertLessThanOrEqual(old.frame.maxX, screen.maxX - 8)
        presenter.show("Vymazať", at: anchor)
        XCTAssertFalse(old.isVisible)
        XCTAssertFalse(presenter.panel === old)
        XCTAssertLessThan(try XCTUnwrap(presenter.panel).frame.width, old.frame.width)
    }
}
