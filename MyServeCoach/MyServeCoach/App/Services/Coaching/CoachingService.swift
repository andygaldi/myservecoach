import Foundation

// MARK: - Domain Types

/// A single coaching cue returned by the backend's rule engine.
///
/// Everything from `metric` down is deviation detail added in Phase P6c: the value that failed
/// the rule plus the rule's own metric/joints/threshold spec. Carrying `metric` and `joints` is
/// what lets the overlay renderer draw the measured segment straight from the cue, so adding a
/// rule to `backend/rules.json` needs no matching change here. All are optional — a pre-P6c
/// backend omits them entirely.
struct Cue: Codable, Sendable {
    let ruleId: String
    let phase: String
    let message: String
    let severity: String
    let metric: String?
    let joints: [String]
    let measuredValue: Double?
    let comparison: String?
    let threshold: Double?
    let thresholdMin: Double?
    let thresholdMax: Double?

    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case phase, message, severity, metric, joints, comparison, threshold
        case measuredValue = "measured_value"
        case thresholdMin = "threshold_min"
        case thresholdMax = "threshold_max"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ruleId = try container.decode(String.self, forKey: .ruleId)
        phase = try container.decode(String.self, forKey: .phase)
        message = try container.decode(String.self, forKey: .message)
        severity = try container.decode(String.self, forKey: .severity)
        metric = try container.decodeIfPresent(String.self, forKey: .metric)
        joints = try container.decodeIfPresent([String].self, forKey: .joints) ?? []
        measuredValue = try container.decodeIfPresent(Double.self, forKey: .measuredValue)
        comparison = try container.decodeIfPresent(String.self, forKey: .comparison)
        threshold = try container.decodeIfPresent(Double.self, forKey: .threshold)
        thresholdMin = try container.decodeIfPresent(Double.self, forKey: .thresholdMin)
        thresholdMax = try container.decodeIfPresent(Double.self, forKey: .thresholdMax)
    }

    init(
        ruleId: String,
        phase: String,
        message: String,
        severity: String,
        metric: String? = nil,
        joints: [String] = [],
        measuredValue: Double? = nil,
        comparison: String? = nil,
        threshold: Double? = nil,
        thresholdMin: Double? = nil,
        thresholdMax: Double? = nil
    ) {
        self.ruleId = ruleId
        self.phase = phase
        self.message = message
        self.severity = severity
        self.metric = metric
        self.joints = joints
        self.measuredValue = measuredValue
        self.comparison = comparison
        self.threshold = threshold
        self.thresholdMin = thresholdMin
        self.thresholdMax = thresholdMax
    }
}

/// Where a detected phase landed in the frames that were posted for analysis. Keypoints aren't
/// repeated over the wire — the caller already holds the frames from `/v1/segment/video`, so
/// `frameIndex` is enough to join back to the original.
struct PhaseDetection: Codable, Sendable {
    let phase: String
    let frameIndex: Int
    let timestamp: Double

    enum CodingKeys: String, CodingKey {
        case phase, timestamp
        case frameIndex = "frame_index"
    }
}

/// The result of a backend serve analysis request. Mirrors the backend's `AnalyzeResponse`.
struct CoachingResult: Codable, Sendable {
    let cues: [Cue]
    let summary: String?
    let phases: [PhaseDetection]

    enum CodingKeys: String, CodingKey {
        case cues, summary, phases
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cues = try container.decode([Cue].self, forKey: .cues)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        phases = try container.decodeIfPresent([PhaseDetection].self, forKey: .phases) ?? []
    }

    init(cues: [Cue], summary: String?, phases: [PhaseDetection] = []) {
        self.cues = cues
        self.summary = summary
        self.phases = phases
    }
}

// MARK: - Protocol

/// Posts keypoints to the FastAPI backend and returns coaching cues.
protocol CoachingServiceProtocol {
    func analyze(
        frames: [BackendFrame],
        detections: [[BackendDetection]]?,
        sessionId: String?
    ) async throws -> CoachingResult
}

// MARK: - Live Implementation

/// URLSession-backed implementation targeting the backend's `POST /v1/analyze`.
/// First caller lands in Phase P6 (Pro 2D Assessment) — see phase P1's requirements.md
/// for why this was built dormant/uncalled originally.
final class LiveCoachingService: CoachingServiceProtocol {
    private struct RequestBody: Encodable {
        let frames: [BackendFrame]
        let detections: [[BackendDetection]]?
        let sessionId: String?

        enum CodingKeys: String, CodingKey {
            case frames, detections
            case sessionId = "session_id"
        }
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func analyze(
        frames: [BackendFrame],
        detections: [[BackendDetection]]? = nil,
        sessionId: String? = nil
    ) async throws -> CoachingResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/analyze"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(frames: frames, detections: detections, sessionId: sessionId)
        )

        return try await sendAndDecode(request, session: session)
    }
}
