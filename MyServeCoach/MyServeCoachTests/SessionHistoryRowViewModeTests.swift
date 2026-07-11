import Foundation
import Testing
@testable import MyServeCoach

@Suite("SessionHistoryRowView Mode Tests")
struct SessionHistoryRowViewModeTests {

    @Test("a lite-mode session is not flagged as Pro")
    func liteSessionIsNotPro() {
        let session = ServeSession(inputType: "recorded", videoURL: nil, mode: "lite")
        let row = SessionHistoryRowView(session: session)
        #expect(row.isProSession == false)
    }

    @Test("a pro2d-mode session is flagged as Pro")
    func pro2dSessionIsPro() {
        let session = ServeSession(inputType: "recorded", videoURL: nil, mode: "pro2d")
        let row = SessionHistoryRowView(session: session)
        #expect(row.isProSession == true)
    }

    @Test("proSubtitle reports the correct serve and cue counts")
    func proSubtitleReportsCounts() {
        let session = ServeSession(inputType: "recorded", videoURL: nil, mode: "pro2d")
        let result1 = ServeResult(serveIndex: 0, summary: nil)
        result1.cues = [CueRecord(ruleId: "a", phase: "contact", message: "m", severity: "major")]
        let result2 = ServeResult(serveIndex: 1, summary: "clean")
        session.results = [result1, result2]
        let row = SessionHistoryRowView(session: session)

        #expect(row.proSubtitle == "2 serves · 1 cue")
    }

    @Test("proSubtitle uses singular wording for a single serve and zero cues")
    func proSubtitleSingularWording() {
        let session = ServeSession(inputType: "recorded", videoURL: nil, mode: "pro2d")
        session.results = [ServeResult(serveIndex: 0, summary: "clean")]
        let row = SessionHistoryRowView(session: session)

        #expect(row.proSubtitle == "1 serve · 0 cues")
    }
}
