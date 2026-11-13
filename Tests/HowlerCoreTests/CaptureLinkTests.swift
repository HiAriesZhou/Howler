import XCTest
@testable import HowlerCore

final class CaptureLinkTests: XCTestCase {
    func testExactCaptureLinkIsAccepted() throws {
        for raw in ["howler://capture", "howler://capture/", "HOWLER://Capture"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertTrue(CaptureLink.requestsCapture(url), raw)
        }
    }

    func testAnythingBeyondTheActionIsIgnored() throws {
        let rejected = [
            "howler://capture?question=hello",
            "howler://capture#region",
            "howler://capture/extra",
            "howler://capture:80",
            "howler://user@capture",
            "howler://open",
            "https://example.com/capture",
            "howler:///capture",
        ]
        for raw in rejected {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertFalse(CaptureLink.requestsCapture(url), raw)
        }
    }

    func testARequestWaitsUntilTheAppCanCapture() {
        var gate = CaptureLinkGate()
        XCTAssertFalse(gate.receive([URL(string: "howler://capture")!]))
        XCTAssertFalse(gate.receive([URL(string: "howler://capture?x=1")!]))
        XCTAssertTrue(gate.becomeReady())
        XCTAssertFalse(gate.becomeReady())
    }

    func testALaterLinkStartsImmediatelyOnceReady() {
        var gate = CaptureLinkGate()
        XCTAssertFalse(gate.becomeReady())
        XCTAssertFalse(gate.receive([URL(string: "https://example.com")!]))
        XCTAssertTrue(gate.receive([
            URL(string: "howler://open")!,
            URL(string: "howler://capture")!,
        ]))
        XCTAssertTrue(gate.receive([URL(string: "howler://capture/")!]))
    }
}
