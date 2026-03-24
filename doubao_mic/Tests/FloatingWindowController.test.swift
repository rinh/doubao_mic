import XCTest
@testable import VoiceInput

@MainActor
final class FloatingWindowControllerTests: XCTestCase {

    func test_createFloatingWindowController() {
        let controller = FloatingWindowController()
        XCTAssertNotNil(controller)
    }

    func test_micViewIsCreated() {
        let controller = FloatingWindowController()
        XCTAssertNotNil(controller.micView)
    }

    func test_windowIsNotVisibleInitially() {
        let controller = FloatingWindowController()
        XCTAssertFalse(controller.window?.isVisible ?? false)
    }

    func test_hide_hidesMicAndDraftWindows_whenVisible() {
        let controller = FloatingWindowController()
        controller.show()
        controller.updateDraftText("draft", phase: .draft)

        XCTAssertTrue(controller.isMicWindowVisibleForTesting())
        XCTAssertTrue(controller.isDraftWindowVisibleForTesting())

        controller.hide()

        XCTAssertFalse(controller.isMicWindowVisibleForTesting())
        XCTAssertFalse(controller.isDraftWindowVisibleForTesting())
    }

    func test_hide_hidesDraftWindow_evenWhenMicAlreadyHidden() {
        let controller = FloatingWindowController()
        controller.show()
        controller.updateDraftText("draft", phase: .draft)
        controller.window?.orderOut(nil)

        XCTAssertFalse(controller.isMicWindowVisibleForTesting())
        XCTAssertTrue(controller.isDraftWindowVisibleForTesting())

        controller.hide()

        XCTAssertFalse(controller.isDraftWindowVisibleForTesting())
    }

    func test_draftWindow_sizeCapsWidthAndGrowsHeight_forLongText() {
        let draftWindow = DraftWindow()
        let maxWidth: CGFloat = 320
        let longText = String(repeating: "长文本用于测试宽度封顶。", count: 24)
        draftWindow.update(state: DraftState(text: longText, phase: .draft, updatedAt: Date()))
        draftWindow.recalculateSize(maxWidth: maxWidth)
        let frameWidth1 = draftWindow.frame.width
        let height1 = draftWindow.contentRect(forFrameRect: draftWindow.frame).height

        let longerText = longText + String(repeating: "继续追加更多内容，验证高度增长。", count: 50)
        draftWindow.update(state: DraftState(text: longerText, phase: .draft, updatedAt: Date()))
        draftWindow.recalculateSize(maxWidth: maxWidth)
        let frameWidth2 = draftWindow.frame.width
        let height2 = draftWindow.contentRect(forFrameRect: draftWindow.frame).height

        XCTAssertLessThanOrEqual(frameWidth1, maxWidth + 0.5)
        XCTAssertLessThanOrEqual(frameWidth2, maxWidth + 0.5)
        XCTAssertEqual(frameWidth1, frameWidth2, accuracy: 1.0)
        XCTAssertGreaterThan(height2, height1)
    }

    func test_draftWindow_absoluteCap900_thenHeightGrows() {
        let draftWindow = DraftWindow()
        let maxWidth: CGFloat = 900
        let longNoSpace = String(repeating: "超长无空格文本ABCDEFGHIJKL1234567890", count: 120)
        draftWindow.update(state: DraftState(text: longNoSpace, phase: .draft, updatedAt: Date()))
        draftWindow.recalculateSize(maxWidth: maxWidth)
        let frameWidth1 = draftWindow.frame.width
        let height1 = draftWindow.contentRect(forFrameRect: draftWindow.frame).height

        let longerNoSpace = longNoSpace + String(repeating: "继续追加无空格内容ZYXWVUT9876543210", count: 220)
        draftWindow.update(state: DraftState(text: longerNoSpace, phase: .draft, updatedAt: Date()))
        draftWindow.recalculateSize(maxWidth: maxWidth)
        let frameWidth2 = draftWindow.frame.width
        let height2 = draftWindow.contentRect(forFrameRect: draftWindow.frame).height

        XCTAssertEqual(frameWidth1, 900, accuracy: 1.0)
        XCTAssertEqual(frameWidth2, 900, accuracy: 1.0)
        XCTAssertGreaterThan(height2, height1)
    }

    func test_draftWindow_horizontalCenter_matchesScreenMidX() {
        let controller = FloatingWindowController()
        controller.show()
        controller.updateDraftText(String(repeating: "超长无空格文本ABCDEFGHIJKL1234567890", count: 120), phase: .draft)

        let centerX = controller.currentDraftWindowCenterXForTesting()
        let screenMidX = controller.currentDraftScreenMidXForTesting()

        XCTAssertEqual(centerX, screenMidX, accuracy: 1.0)
    }

    func test_screenSource_isActiveSpace() {
        let controller = FloatingWindowController()
        XCTAssertEqual(controller.currentScreenSourceForTesting(), "activeSpace")
    }

    func test_draftWindow_userProvidedText_growsHeight_atFixedWidth360() {
        let draftWindow = DraftWindow()
        let userText = "不是，我我这个没有撑高，你那 case 怎么撑高的我不知道，反正我这个没有撑高。我现在说的这这句话，你把它输入进去，它就没有撑高"
        let shortText = "短句"

        draftWindow.update(state: DraftState(text: shortText, phase: .draft, updatedAt: Date()))
        draftWindow.recalculateSize(maxWidth: 360)
        let baseHeight = draftWindow.contentRect(forFrameRect: draftWindow.frame).height

        draftWindow.update(state: DraftState(text: userText, phase: .draft, updatedAt: Date()))
        draftWindow.recalculateSize(maxWidth: 360)

        let contentRect = draftWindow.contentRect(forFrameRect: draftWindow.frame)
        XCTAssertEqual(contentRect.width, 360, accuracy: 1.0)
        XCTAssertGreaterThan(contentRect.height, baseHeight, "User-provided text should wrap and grow height")
    }

    func test_draftWindow_wrapsAndGrowsHeight_whenMaxWidthIs720() {
        let draftWindow = DraftWindow()
        let shortText = "短句"
        let longText = String(
            repeating: "我们先重新试一下，看看它能不能把宽度限制住。如果没能限制住，那就说明你这次改动有问题；要是真出问题了，我们暂时也不知道哪里有问题，得再重新排查一下。",
            count: 12
        )

        draftWindow.update(state: DraftState(text: shortText, phase: .draft, updatedAt: Date()))
        draftWindow.recalculateSize(maxWidth: 720)
        let baseHeight = draftWindow.contentRect(forFrameRect: draftWindow.frame).height

        draftWindow.update(state: DraftState(text: longText, phase: .draft, updatedAt: Date()))
        draftWindow.recalculateSize(maxWidth: 720)
        let contentRect = draftWindow.contentRect(forFrameRect: draftWindow.frame)

        XCTAssertEqual(contentRect.width, 720, accuracy: 1.0)
        XCTAssertGreaterThan(contentRect.height, baseHeight)
    }
}
