import XCTest

final class WaveformUITests: XCTestCase {

    func test_waveformFixture_drivesAccessibilityValue_lowHighLow() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-waveform")

        guard let fixtureURL = Bundle(for: Self.self).url(forResource: "waveform_fixture", withExtension: "wav") else {
            XCTFail("Missing waveform_fixture.wav in UI test bundle")
            return
        }
        app.launchArguments.append("--fixture-path=\(fixtureURL.path)")

        app.launch()

        let waveformProbe = app.staticTexts["waveform_probe_value"]
        XCTAssertTrue(waveformProbe.waitForExistence(timeout: 5), "Waveform probe should appear")

        var values: [String] = []
        let deadline = Date().addingTimeInterval(2.2)
        while Date() < deadline {
            if let value = waveformProbe.value as? String, !value.isEmpty {
                values.append(value)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        }

        XCTAssertGreaterThan(values.count, 8, "Should sample enough waveform values")
        let centerHeights = values.compactMap(Self.centerBarHeight(from:))
        XCTAssertGreaterThan(centerHeights.count, 8, "Should parse center bar heights")

        guard let minValue = centerHeights.min(),
              let maxValue = centerHeights.max() else {
            XCTFail("No waveform values parsed")
            return
        }

        XCTAssertGreaterThan(maxValue - minValue, 4.0, "Waveform should show obvious amplitude changes")

        let peakIndex = centerHeights.firstIndex(of: maxValue) ?? 0
        let tail = centerHeights.suffix(from: peakIndex)
        let lowAfterPeak = tail.contains { $0 <= (minValue + 1.5) }
        XCTAssertTrue(lowAfterPeak, "Waveform should drop after peak to reflect trailing silence")
    }

    private static func centerBarHeight(from value: String) -> Double? {
        let parts = value.split(separator: ",").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        return parts[1]
    }

    func test_draftWindowWidth_resetsToDefaultAtNextSessionStart() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-draft-window")
        app.launch()

        let probe = app.staticTexts["draft_window_width_probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "Draft width probe should appear")

        var latestValue = ""
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if let value = probe.value as? String, !value.isEmpty {
                latestValue = value
                if value.hasPrefix("reset:") { break }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertTrue(latestValue.hasPrefix("reset:"), "Should reach reset stage, got \(latestValue)")
        let widthText = latestValue.replacingOccurrences(of: "reset:", with: "")
        guard let width = Double(widthText) else {
            XCTFail("Unable to parse width from probe value: \(latestValue)")
            return
        }
        XCTAssertEqual(width, 360.0, accuracy: 1.0, "Draft width should reset to default")
    }

    func test_polishHotkey_flow_draft_finish_polish_inserted() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-polish-flow")
        app.launchArguments.append("--fixture-asr-final=语音原始识别文本")
        app.launchArguments.append("--fixture-seed-output=语音整理后文本")
        app.launch()

        let probe = app.staticTexts["polish_flow_probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "Polish flow probe should appear")

        var history: [String] = []
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if let value = probe.value as? String, !value.isEmpty {
                history.append(value)
                if value.hasPrefix("inserted:") {
                    break
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let merged = history.joined(separator: "|")
        XCTAssertTrue(merged.contains("state:draft"), "Should enter draft state")
        XCTAssertTrue(merged.contains("state:finish"), "Should enter finish state")
        XCTAssertTrue(merged.contains("state:polish"), "Should enter polish state")
        XCTAssertTrue(merged.contains("inserted:语音整理后文本"), "Should insert polished text")

        let hideDeadline = Date().addingTimeInterval(2.5)
        var hiddenObserved = false
        while Date() < hideDeadline {
            if let value = probe.value as? String, value.contains("hidden:true") {
                hiddenObserved = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }
        XCTAssertTrue(hiddenObserved, "Floating UI should hide around 1 second after insertion")
    }

    func test_polishHotkey_flow_keepsFloatingVisible_untilInsertionThenHides() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-polish-flow")
        app.launchArguments.append("--fixture-asr-final=语音原始识别文本")
        app.launchArguments.append("--fixture-seed-output=语音整理后文本")
        app.launch()

        let probe = app.staticTexts["polish_flow_probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "Polish flow probe should appear")

        var insertedSeen = false
        let insertedDeadline = Date().addingTimeInterval(2.0)
        while Date() < insertedDeadline {
            let value = (probe.value as? String) ?? ""
            XCTAssertFalse(
                value.contains("hidden:true"),
                "Floating UI should not hide before insertion, current probe=\(value)"
            )
            if value.contains("inserted:语音整理后文本") {
                insertedSeen = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(insertedSeen, "Insertion should occur in polish flow")

        let hideDeadline = Date().addingTimeInterval(2.5)
        var finalValue = (probe.value as? String) ?? ""
        while Date() < hideDeadline {
            finalValue = (probe.value as? String) ?? ""
            if finalValue.contains("hidden:true") {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(finalValue.contains("hidden:true"), "Floating UI should hide after insertion, probe=\(finalValue)")

        let insertedRange = finalValue.range(of: "inserted:语音整理后文本")
        let hiddenRange = finalValue.range(of: "hidden:true")
        XCTAssertNotNil(insertedRange, "Final probe should include insertion marker")
        XCTAssertNotNil(hiddenRange, "Final probe should include hidden marker")
        if let insertedRange, let hiddenRange {
            XCTAssertLessThan(
                finalValue.distance(from: finalValue.startIndex, to: insertedRange.lowerBound),
                finalValue.distance(from: finalValue.startIndex, to: hiddenRange.lowerBound),
                "Hidden marker must appear after insertion marker"
            )
        }
    }

    func test_draftWindowSize_capsAtHalfScreenWidth_thenGrowsHeight() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-draft-sizing-cap")
        app.launch()

        let probe = app.staticTexts["draft_window_size_probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "Draft size probe should appear")

        var case1Raw = ""
        var case2Raw = ""
        var case3Raw = ""
        var lastRaw = ""
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if let value = probe.value as? String {
                lastRaw = value
                if let extractedCase1 = Self.extractStage("case1", from: value) {
                    case1Raw = extractedCase1
                }
                if let extractedCase2 = Self.extractStage("case2", from: value) {
                    case2Raw = extractedCase2
                }
                if let extractedCase3 = Self.extractStage("case3", from: value) {
                    case3Raw = extractedCase3
                    break
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }
        print("[DraftSizingProbe] merged=\(lastRaw)")
        print("[DraftSizingProbe] case1Raw=\(case1Raw)")
        print("[DraftSizingProbe] case2Raw=\(case2Raw)")
        print("[DraftSizingProbe] case3Raw=\(case3Raw)")

        let case1 = Self.parseSizeProbe(case1Raw)
        let case2 = Self.parseSizeProbe(case2Raw)
        let case3 = Self.parseSizeProbe(case3Raw)
        if let s1 = case1 {
            print("[DraftSizingProbe] case1 parsed cw=\(s1.contentWidth), fw=\(s1.frameWidth), ch=\(s1.contentHeight), fh=\(s1.frameHeight), maxfw=\(s1.maxFW), sw=\(s1.screenWidth), sh=\(s1.screenHeight), x=\(s1.x), screenMidX=\(s1.screenMidX), cx=\(s1.centerX)")
        } else {
            print("[DraftSizingProbe] case1 parse failed")
        }
        if let s2 = case2 {
            print("[DraftSizingProbe] case2 parsed cw=\(s2.contentWidth), fw=\(s2.frameWidth), ch=\(s2.contentHeight), fh=\(s2.frameHeight), maxfw=\(s2.maxFW), sw=\(s2.screenWidth), sh=\(s2.screenHeight), x=\(s2.x), screenMidX=\(s2.screenMidX), cx=\(s2.centerX)")
        } else {
            print("[DraftSizingProbe] case2 parse failed")
        }
        if let s3 = case3 {
            print("[DraftSizingProbe] case3 parsed cw=\(s3.contentWidth), fw=\(s3.frameWidth), ch=\(s3.contentHeight), fh=\(s3.frameHeight), maxfw=\(s3.maxFW), sw=\(s3.screenWidth), sh=\(s3.screenHeight), x=\(s3.x), screenMidX=\(s3.screenMidX), cx=\(s3.centerX)")
        } else {
            print("[DraftSizingProbe] case3 parse failed")
        }
        XCTAssertNotNil(case1, "Should parse case1 probe value: \(case1Raw)")
        XCTAssertNotNil(case2, "Should parse case2 probe value: \(case2Raw)")
        XCTAssertNotNil(case3, "Should parse case3 probe value: \(case3Raw)")
        XCTAssertTrue(case1Raw.contains("ss=activeSpace"), "Case1 should use activeSpace screen source: \(case1Raw)")
        XCTAssertTrue(case2Raw.contains("ss=activeSpace"), "Case2 should use activeSpace screen source: \(case2Raw)")
        XCTAssertTrue(case3Raw.contains("ss=activeSpace"), "Case3 should use activeSpace screen source: \(case3Raw)")
        guard let c1 = case1, let c2 = case2, let c3 = case3 else { return }

        // case1: below max width -> default 360 and centered
        XCTAssertEqual(c1.frameWidth, 360.0, accuracy: 1.0, "Short text should keep default width")
        XCTAssertEqual(c1.centerX, c1.screenMidX, accuracy: 1.0, "Case1 should stay centered")

        // case2: over max width -> clamp to maxfw and centered
        XCTAssertEqual(c2.frameWidth, c2.maxFW, accuracy: 1.0, "Long text should clamp width to maxfw")
        XCTAssertEqual(c2.centerX, c2.screenMidX, accuracy: 1.0, "Case2 should stay centered")

        // case3: with width already capped, extra text should grow height
        XCTAssertEqual(c3.frameWidth, c2.frameWidth, accuracy: 1.0, "Width should stay fixed after reaching max")
        XCTAssertGreaterThan(c3.frameHeight, c2.frameHeight, "Frame height should grow for longer text")
        XCTAssertEqual(c3.centerX, c3.screenMidX, accuracy: 1.0, "Case3 should stay centered")
    }

    private static func parseSizeProbe(_ raw: String) -> (contentWidth: Double, frameWidth: Double, contentHeight: Double, frameHeight: Double, maxFW: Double, screenWidth: Double, screenHeight: Double, x: Double, screenMidX: Double, centerX: Double)? {
        guard !raw.isEmpty else { return nil }
        var values: [String: Double] = [:]
        raw.split(separator: ";").forEach { part in
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, let num = Double(kv[1]) else { return }
            let normalizedKey = kv[0].split(separator: ":").last.map(String.init) ?? kv[0]
            values[normalizedKey] = num
        }
        guard let contentWidth = values["cw"],
              let frameWidth = values["fw"],
              let contentHeight = values["ch"],
              let frameHeight = values["fh"],
              let maxFW = values["maxfw"],
              let screenWidth = values["sw"],
              let screenHeight = values["sh"],
              let x = values["x"],
              let screenMidX = values["screenMidX"],
              let centerX = values["cx"] else {
            return nil
        }
        return (contentWidth, frameWidth, contentHeight, frameHeight, maxFW, screenWidth, screenHeight, x, screenMidX, centerX)
    }

    private static func extractStage(_ stage: String, from merged: String) -> String? {
        let entries = merged.split(separator: "|").map(String.init)
        return entries.first(where: { $0.hasPrefix("\(stage):") })
    }
}
