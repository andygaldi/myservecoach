# Phase P6 — Plan

> **Lite-isolation note:** no group modifies `PhaseReviewView`, the Lite pipeline/segmentation
> services (`PoseAnalysisPipeline`, `PoseEstimationService`, `ServeSegmentationService`,
> `PhaseGuesser`), or `ContentView`. The mode selector lives inside `VideoSourceSelectionView`
> itself; selecting Lite leaves every existing call in that view's Lite branch unchanged.

> **Shared naming note:** all new Swift networking/model types use a `Backend`/`Pro` prefix
> where a name would otherwise collide with an existing Lite type — e.g. `BackendDetection` (vs.
> the backend's `Detection`), `ProServeAnalysisPipeline` (vs. Lite's `PoseAnalysisPipeline`). The
> six-frame backend phase keys (`start`/`release`/`trophy_pose`/`racket_drop`/`contact`/`finish`)
> are consumed as raw `String`s throughout iOS — they are unrelated to Lite's 3-case `ServePhase`
> enum in `App/Models/ServePhase.swift`, which is not touched.

## Group 1 — Backend: `POST /v1/segment` (surface: `backend`)

1. In `backend/app/engine/phases.py`, add (near `segment_serves`, after its definition):
   ```python
   def slice_detections_by_segments(
       detections: list[list[Detection]], segments: list[list[Frame]]
   ) -> list[list[list[Detection]]]:
       """Slice a flat per-frame detections list at the same boundaries segment_serves used for frames."""
       serve_detections: list[list[list[Detection]]] = []
       cursor = 0
       for segment in segments:
           serve_detections.append(detections[cursor : cursor + len(segment)])
           cursor += len(segment)
       return serve_detections
   ```
   (Moved verbatim from `backend/tools/segmentation_report.py`, which currently defines it as a
   module-level function — same docstring, same body.)
2. In `backend/tools/segmentation_report.py`: delete the local `slice_detections_by_segments`
   definition; add it to the existing `from app.engine.phases import detect_phases, segment_serves`
   import line.
3. In `backend/app/models.py`, add (after `AnalyzeRequest`):
   ```python
   class SegmentRequest(BaseModel):
       frames: list[Frame] = Field(min_length=1)
       detections: list[list[Detection]] | None = None
       session_id: str | None = None


   class ServeSegment(BaseModel):
       frames: list[Frame]
       detections: list[list[Detection]] | None = None


   class SegmentResponse(BaseModel):
       segments: list[ServeSegment]
   ```
4. Create `backend/app/routers/segment.py`:
   ```python
   from fastapi import APIRouter
   from app.models import SegmentRequest, SegmentResponse, ServeSegment
   from app.engine.phases import segment_serves, slice_detections_by_segments

   router = APIRouter()


   @router.post("/segment", response_model=SegmentResponse)
   async def segment(request: SegmentRequest) -> SegmentResponse:
       serve_frames = segment_serves(request.frames)
       if request.detections is not None:
           serve_detections = slice_detections_by_segments(request.detections, serve_frames)
       else:
           serve_detections = [None] * len(serve_frames)
       segments = [
           ServeSegment(frames=frames, detections=dets)
           for frames, dets in zip(serve_frames, serve_detections)
       ]
       return SegmentResponse(segments=segments)
   ```
5. In `backend/app/main.py`, add `segment` to the router import and registration:
   ```python
   from app.routers import analyze, detect, pose, reference_frames, segment
   ...
   app.include_router(segment.router, prefix="/v1")
   ```
6. Create `backend/tests/test_segment_endpoint.py`, mirroring `tests/test_analyze.py`'s style
   (direct FastAPI `TestClient`/`AsyncClient` JSON POST, not multipart):
   - `test_single_continuous_serve_returns_one_segment`: frames with no low-velocity gap → one
     segment containing all frames, `detections` on the response segment `None` when the request
     omitted `detections`.
   - `test_two_serve_sequence_returns_two_segments_with_sliced_detections`: reuse
     `test_segment_serves.py`'s two-serve synthetic frame builder (`_build_two_serve_sequence` or
     equivalent fixture) with a parallel synthetic `detections` list; assert 2 segments, and that
     each segment's `detections` length matches its `frames` length and slices at the same
     boundary `segment_serves` itself produces (assert directly against calling
     `segment_serves`/`slice_detections_by_segments` in the test for the expected split, not a
     hardcoded index).
   - `test_empty_frames_returns_422`: `frames: []` violates `Field(min_length=1)` — assert 422,
     matching `AnalyzeRequest`'s existing empty-frames behavior.
   - `test_detections_omitted_yields_none_per_segment`: no `detections` key in the request body →
     every response segment's `detections` is `null`.
7. Run `pytest backend/tests/test_segment_endpoint.py backend/tests/test_segmentation_report.py -v`
   — confirm new tests pass and `segmentation_report.py`'s existing tests are unaffected by the
   helper's relocation.
8. Run `pytest backend/` (full suite) — confirm zero regressions.

## Group 2 — iOS: Detection Types, `CoachingService` Extension, Multipart Encoder (surface: `ios`)

9. Create `App/Models/BackendDetection.swift`:
   ```swift
   import Foundation

   struct BackendBoundingBox: Codable, Sendable {
       let xMin: Float
       let yMin: Float
       let xMax: Float
       let yMax: Float

       enum CodingKeys: String, CodingKey {
           case xMin = "x_min", yMin = "y_min", xMax = "x_max", yMax = "y_max"
       }
   }

   struct BackendDetection: Codable, Sendable {
       let label: String
       let confidence: Float
       let bbox: BackendBoundingBox
   }
   ```
10. In `App/Services/Coaching/CoachingService.swift`:
    - Update the protocol:
      ```swift
      protocol CoachingServiceProtocol {
          func analyze(
              frames: [BackendFrame],
              detections: [[BackendDetection]]?,
              sessionId: String?
          ) async throws -> CoachingResult
      }
      ```
    - Update `LiveCoachingService.RequestBody` and `analyze`:
      ```swift
      private struct RequestBody: Encodable {
          let frames: [BackendFrame]
          let detections: [[BackendDetection]]?
          let sessionId: String?

          enum CodingKeys: String, CodingKey {
              case frames, detections
              case sessionId = "session_id"
          }
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
          let (data, response) = try await URLSession.shared.data(for: request)
          guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
              let status = (response as? HTTPURLResponse)?.statusCode ?? -1
              throw CoachingServiceError.networkError("HTTP \(status)")
          }
          return try JSONDecoder().decode(CoachingResult.self, from: data)
      }
      ```
      (Default-`nil` params keep this source-compatible with any future single-serve-only caller.)
11. Create `App/Services/Networking/MultipartFormEncoder.swift`:
    ```swift
    import Foundation

    /// Builds `multipart/form-data` bodies matching FastAPI's `File(...)`/`Form(...)` expectations:
    /// repeated `frames` file parts (one per JPEG) and repeated `timestamps` text parts (one per
    /// value, not a JSON array) — see backend/tests/test_pose_endpoint.py for the wire contract.
    struct MultipartFormEncoder {
        let boundary = "Boundary-\(UUID().uuidString)"

        var contentType: String { "multipart/form-data; boundary=\(boundary)" }

        func encodeFrames(_ frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) -> Data {
            var body = Data()
            for (index, frame) in frames.enumerated() {
                appendFilePart(
                    to: &body, name: "frames", filename: "frame\(index).jpg",
                    mimeType: "image/jpeg", fileData: frame.jpegData
                )
            }
            for frame in frames {
                appendTextPart(to: &body, name: "timestamps", value: String(frame.timestamp))
            }
            if let sessionId {
                appendTextPart(to: &body, name: "session_id", value: sessionId)
            }
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            return body
        }

        private func appendFilePart(
            to body: inout Data, name: String, filename: String, mimeType: String, fileData: Data
        ) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                    .data(using: .utf8)!
            )
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }

        private func appendTextPart(to body: inout Data, name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
    }
    ```
12. Create `MyServeCoachTests/MultipartFormEncoderTests.swift`: build a 2-frame body, split the
    raw `Data` on `--\(boundary)` (decode to a UTF-8-lossy string for text parts; for the file
    parts, assert the `Content-Disposition`/`Content-Type` header lines and that the raw JPEG
    bytes appear unmodified in the part body), and assert:
    - Exactly 2 `frames` file parts, each with `filename="frame0.jpg"`/`"frame1.jpg"` and
      `Content-Type: image/jpeg`.
    - Exactly 2 `timestamps` text parts with the expected string values (not one JSON-array part).
    - `session_id` part present only when a non-nil `sessionId` is passed, absent otherwise.
    - Body ends with the closing `--boundary--` delimiter.
13. Create `MyServeCoachTests/CoachingServiceRequestEncodingTests.swift`: encode a `RequestBody`-
    shaped value (or capture the actual `URLRequest.httpBody` via a `URLProtocol` stub, matching
    whatever's simplest given `LiveCoachingService` has no injectable session — prefer adding a
    `URLSession` init parameter to `LiveCoachingService` now, defaulting to `.shared`, purely to
    make this and Group 3/4's live-service tests possible without hitting the network) and assert
    the encoded JSON's top-level keys are exactly `frames`, `detections`, `session_id`, and that a
    `nil` `detections` encodes as JSON `null` (not an omitted key — `Encodable`'s default optional
    behavior already does this; just lock it in with a test).
14. Run `xcodebuild test` via `scripts/verify.sh ios` scoped to the new test files (or the full
    suite) — confirm green.

## Group 3 — iOS: Pro Upload Services (surface: `ios`)

15. Add a `URLSession` init parameter (default `.shared`) to `LiveCoachingService` (per step 13)
    if not already done there.
16. Create `App/Services/Pose/PoseUploadService.swift`:
    ```swift
    import Foundation

    protocol PoseUploadServiceProtocol {
        func infer(frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) async throws -> [BackendFrame]
    }

    final class LivePoseUploadService: PoseUploadServiceProtocol {
        private let baseURL: URL
        private let session: URLSession
        private let encoder = MultipartFormEncoder()

        init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
            self.baseURL = baseURL
            self.session = session
        }

        func infer(frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) async throws -> [BackendFrame] {
            var request = URLRequest(url: baseURL.appendingPathComponent("v1/pose"))
            request.httpMethod = "POST"
            request.setValue(encoder.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = encoder.encodeFrames(frames, sessionId: sessionId)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw ProUploadError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            struct PoseResponse: Decodable { let frames: [BackendFrame] }
            return try JSONDecoder().decode(PoseResponse.self, from: data).frames
        }
    }

    enum ProUploadError: Error {
        case networkError(String)
    }
    ```
17. Create `App/Services/Pose/ObjectDetectionUploadService.swift`, same shape POSTing to
    `v1/detect`, decoding:
    ```swift
    struct BackendDetectionFrame: Decodable, Sendable {
        let timestamp: Double
        let detections: [BackendDetection]
    }
    protocol ObjectDetectionUploadServiceProtocol {
        func infer(frames: [(timestamp: Double, jpegData: Data)], sessionId: String?) async throws -> [BackendDetectionFrame]
    }
    final class LiveObjectDetectionUploadService: ObjectDetectionUploadServiceProtocol { /* mirrors LivePoseUploadService, decodes {frames: [BackendDetectionFrame]} */ }
    ```
18. Create `App/Services/Pose/ServeSegmentationUploadService.swift` — JSON POST (not multipart) to
    `v1/segment`:
    ```swift
    import Foundation

    struct ProServeSegment: Decodable, Sendable {
        let frames: [BackendFrame]
        let detections: [[BackendDetection]]?
    }

    protocol ServeSegmentationUploadServiceProtocol {
        func segment(frames: [BackendFrame], detections: [[BackendDetection]]?, sessionId: String?) async throws -> [ProServeSegment]
    }

    final class LiveServeSegmentationUploadService: ServeSegmentationUploadServiceProtocol {
        private struct RequestBody: Encodable {
            let frames: [BackendFrame]
            let detections: [[BackendDetection]]?
            let sessionId: String?
            enum CodingKeys: String, CodingKey { case frames, detections; case sessionId = "session_id" }
        }
        private struct SegmentResponseBody: Decodable { let segments: [ProServeSegment] }

        private let baseURL: URL
        private let session: URLSession

        init(baseURL: URL = BackendConfig.baseURL, session: URLSession = .shared) {
            self.baseURL = baseURL
            self.session = session
        }

        func segment(frames: [BackendFrame], detections: [[BackendDetection]]?, sessionId: String?) async throws -> [ProServeSegment] {
            var request = URLRequest(url: baseURL.appendingPathComponent("v1/segment"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(RequestBody(frames: frames, detections: detections, sessionId: sessionId))
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw ProUploadError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            return try JSONDecoder().decode(SegmentResponseBody.self, from: data).segments
        }
    }
    ```
19. Create tests for all three services using a `URLProtocol`-stubbing helper (new
    `MyServeCoachTests/Support/StubURLProtocol.swift` — intercepts requests, returns a canned
    response/data/error, and captures the last request for assertion; registered on a
    `URLSessionConfiguration.ephemeral`-backed session passed into each service's `session:` init
    param): one success-path test per service (asserts decoded result matches the stubbed JSON),
    one non-2xx-status test per service (asserts `ProUploadError.networkError` thrown), one
    malformed-JSON test per service (asserts a decoding error propagates, not silently swallowed).
20. Run `scripts/verify.sh ios` — confirm green.

## Group 4 — iOS: `ProServeAnalysisPipeline` Orchestration (surface: `ios`)

21. Create `App/Services/Pose/ProServeAnalysisPipeline.swift`:
    ```swift
    import AVFoundation
    import UIKit

    enum ProPoseConstants {
        /// P4b validated stride 2 against real footage for the off-device pipeline — denser than
        /// Lite's Vision-tuned PoseConstants.kPoseSampleStride (3), specifically so fast swings
        /// can't fall entirely between two sampled frames.
        static let kStride: Int = 2
    }

    struct AssessmentServeResult: Sendable {
        let serveIndex: Int
        let coaching: CoachingResult
    }

    protocol ProServeAnalyzing: Sendable {
        func analyze(videoURL: URL) async throws -> [AssessmentServeResult]
    }

    actor ProServeAnalysisPipeline: ProServeAnalyzing {
        private let sampler: FrameSamplerService
        private let poseUploader: any PoseUploadServiceProtocol
        private let detectionUploader: any ObjectDetectionUploadServiceProtocol
        private let segmentationUploader: any ServeSegmentationUploadServiceProtocol
        private let coachingService: any CoachingServiceProtocol

        init(
            sampler: FrameSamplerService = FrameSamplerService(),
            poseUploader: any PoseUploadServiceProtocol = LivePoseUploadService(),
            detectionUploader: any ObjectDetectionUploadServiceProtocol = LiveObjectDetectionUploadService(),
            segmentationUploader: any ServeSegmentationUploadServiceProtocol = LiveServeSegmentationUploadService(),
            coachingService: any CoachingServiceProtocol = LiveCoachingService()
        ) {
            self.sampler = sampler
            self.poseUploader = poseUploader
            self.detectionUploader = detectionUploader
            self.segmentationUploader = segmentationUploader
            self.coachingService = coachingService
        }

        func analyze(videoURL: URL) async throws -> [AssessmentServeResult] {
            let asset = AVURLAsset(url: videoURL)
            let sampled = try await sampleAtStride(asset: asset, stride: ProPoseConstants.kStride)
            let jpegFrames = sampled.map { (timestamp: CMTimeGetSeconds($0.time), jpegData: Self.jpegData(from: $0.image)) }

            async let poseFrames = poseUploader.infer(frames: jpegFrames, sessionId: nil)
            async let detectionFrames = detectionUploader.infer(frames: jpegFrames, sessionId: nil)
            let (frames, detections) = try await (poseFrames, detectionFrames)

            let orderedDetections = frames.map { frame in
                detectionFrames_lookup(detections, timestamp: frame.timestamp)
            }

            let segments = try await segmentationUploader.segment(
                frames: frames, detections: orderedDetections, sessionId: nil
            )

            var results: [AssessmentServeResult] = []
            for (index, segment) in segments.enumerated() {
                let coaching = try await coachingService.analyze(
                    frames: segment.frames, detections: segment.detections, sessionId: nil
                )
                results.append(AssessmentServeResult(serveIndex: index, coaching: coaching))
            }
            return results
        }

        // Reuses FrameSamplerService.makeSampler but overrides the stride so the Pro pipeline
        // doesn't inherit Lite's Vision-tuned PoseConstants.kPoseSampleStride.
        private func sampleAtStride(asset: AVAsset, stride: Int) async throws -> [(time: CMTime, image: CGImage)] {
            // implementation samples asset frames at `stride`, structurally identical to
            // FrameSamplerService.sampleFrames(from:) but parameterized on stride instead of
            // reading PoseConstants.kPoseSampleStride — see FrameSamplerService for the pattern
            // to mirror (track lookup, frameRate/duration load, AVAssetImageGenerator loop).
        }

        private static func jpegData(from image: CGImage) -> Data {
            UIImage(cgImage: image).jpegData(compressionQuality: 0.85) ?? Data()
        }

        private func detectionFrames_lookup(_ detectionFrames: [BackendDetectionFrame], timestamp: Double) -> [BackendDetection] {
            detectionFrames.first(where: { $0.timestamp == timestamp })?.detections ?? []
        }
    }

    enum ProServeAnalysisError: Error {
        case noSegmentsDetected
    }
    ```
   Note for the implementer: `FrameSamplerService.makeSampler`/`sampleFrames` currently read
   `PoseConstants.kPoseSampleStride` directly rather than taking a stride parameter. Either (a)
   add an optional `stride: Int = PoseConstants.kPoseSampleStride` parameter to
   `FrameSamplerService.makeSampler`/`sampleFrames` (preferred — small, backward-compatible
   change, avoids duplicating the sampling loop) and call it with `stride:
   ProPoseConstants.kStride` here, or (b) duplicate the loop as sketched above. Prefer (a); update
   `FrameSamplerServiceTests.swift` to cover the new parameter's default-preserves-behavior case.
22. If no segments are returned (`segments.isEmpty`), throw `ProServeAnalysisError.noSegmentsDetected`
    rather than returning an empty array — gives the caller (Group 5) a distinct error path from
    Lite's `noPoseDetected`, worded appropriately for Pro 2D ("No serves detected in this clip.").
23. Create `MyServeCoachTests/ProServeAnalysisPipelineTests.swift` with mock implementations of
    all four protocol dependencies (`MockPoseUploadService`, `MockObjectDetectionUploadService`,
    `MockServeSegmentationUploadService`, `MockCoachingService` — the latter conforming to the
    now-updated `CoachingServiceProtocol`):
    - `test_ordersResultsBySegmentIndex`: 2 mock segments → 2 `AssessmentServeResult`s with
      `serveIndex` 0 and 1, in order.
    - `test_throwsNoSegmentsDetectedWhenSegmentationReturnsEmpty`.
    - `test_propagatesPoseUploadFailure` / `test_propagatesDetectionUploadFailure` /
      `test_propagatesSegmentationFailure` / `test_propagatesAnalyzeFailure` — each asserts the
      pipeline rethrows rather than swallowing.
    - `test_passesDetectionsAlignedByTimestampToSegmentation` — mock pose/detect responses with
      out-of-order or partially-missing timestamps; assert the detections array passed to the
      segmentation mock is aligned to `frames` by timestamp, not by array position.
24. Run `scripts/verify.sh ios` — confirm green.

## Group 5 — iOS: Mode Selector (surface: `ios`)

25. Create `App/Models/SessionMode.swift`:
    ```swift
    enum SessionMode: String, CaseIterable, Identifiable {
        case lite = "Lite"
        case pro2D = "Pro 2D"
        var id: String { rawValue }
    }
    ```
26. In `App/ViewModels/VideoSourceSelectionViewModel.swift`:
    - Add a persisted mode property (not `@AppStorage` directly — `@Observable` classes don't mix
      cleanly with that property wrapper — backed by `UserDefaults.standard` instead):
      ```swift
      private static let modeDefaultsKey = "com.myservecoach.sessionMode"

      var selectedMode: SessionMode {
          get { SessionMode(rawValue: UserDefaults.standard.string(forKey: Self.modeDefaultsKey) ?? "") ?? .lite }
          set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeDefaultsKey) }
      }
      ```
    - Add a `proPipeline: any ProServeAnalyzing` dependency, injectable in `init` (default
      `ProServeAnalysisPipeline()`), alongside the existing `coordinator`.
    - Add Pro-specific published state: `var navigateToAssessmentResults = false` and
      `var assessmentResults: [AssessmentServeResult]?` (or a small wrapper view model — see
      Group 7; keep this group's addition minimal, just enough to branch and navigate).
    - Branch `runPipeline(on:inputType:)` at its top:
      ```swift
      func runPipeline(on url: URL, inputType: String = "imported") async {
          switch selectedMode {
          case .lite:
              await runLitePipeline(on: url, inputType: inputType)  // existing body, renamed
          case .pro2D:
              await runProPipeline(on: url, inputType: inputType)
          }
      }
      ```
      Rename the existing method body to `runLitePipeline` verbatim (no logic changes — this
      satisfies "Lite path unchanged" since the code itself doesn't change, only its name/call
      site). Add `runProPipeline`:
      ```swift
      @MainActor
      func runProPipeline(on url: URL, inputType: String = "imported") async {
          errorMessage = nil
          if let old = pendingVideoURL {
              try? FileManager.default.removeItem(at: old)
              pendingVideoURL = nil
          }
          do {
              let results = try await proPipeline.analyze(videoURL: url)
              pendingVideoURL = url
              assessmentResults = results
              navigateToAssessmentResults = true
          } catch ProServeAnalysisError.noSegmentsDetected {
              errorMessage = "No serves detected in this clip. Try a different clip."
              try? FileManager.default.removeItem(at: url)
          } catch {
              errorMessage = "Could not analyze video. Try again."
              try? FileManager.default.removeItem(at: url)
              print("[VideoSourceSelection] Pro pipeline error: \(error)")
          }
          isProcessing = false
      }
      ```
27. In `App/Views/VideoSourceSelectionView.swift`, add a segmented `Picker` bound to
    `viewModel.selectedMode`, placed between the title `VStack` and the source-buttons `VStack`:
    ```swift
    Picker("Mode", selection: $viewModel.selectedMode) {
        ForEach(SessionMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
        }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal)
    ```
    Note: `VideoSourceSelectionViewModel` uses `@Observable`, not `@Bindable`-incompatible state —
    confirm `$viewModel.selectedMode` works given the view already declares `@Bindable var
    viewModel: VideoSourceSelectionViewModel` at the top (it does, per the existing file).
    Add a `navigationDestination(isPresented: $viewModel.navigateToAssessmentResults)` pointing at
    the Group 7 results view (stub acceptable in this group if Group 7 hasn't landed yet in the
    same PR — since groups run sequentially in one phase, wire the real view once Group 7 exists).
28. Update `MyServeCoachTests/VideoSourceSelectionViewModelTests.swift`:
    - Add a `MockProServeAnalyzing` conforming to `ProServeAnalyzing`.
    - `test_defaultModeIsLite`.
    - `test_selectedModePersistsAcrossInstancesViaUserDefaults` (set on one VM instance, read on a
      new instance backed by the same `UserDefaults.standard` — clear the key in a `defer` so the
      test doesn't leak state into other tests).
    - `test_proMode_runPipeline_routesToProPipelineNotLiteCoordinator`: set `selectedMode = .pro2D`,
      call `runPipeline`, assert the mock Lite `PoseAnalyzing` pipeline was never invoked and the
      mock Pro pipeline was.
    - `test_proMode_noSegments_setsDistinctErrorMessage`.
    - `test_proMode_success_setsAssessmentResultsAndNavigates`.
    - `test_liteMode_runPipeline_behaviorUnchanged`: re-run the existing Lite-path assertions
      (zero segments / success / failure) with `selectedMode` explicitly `.lite` to lock in
      no-regression.
29. Run `scripts/verify.sh ios` — confirm green.

## Group 6 — iOS: SwiftData Models (surface: `ios`)

30. In `App/Models/SwiftData/ServeSession.swift`, add a `mode` field:
    ```swift
    var mode: String = "lite"
    ```
    Update the `init` to accept it with a default:
    ```swift
    init(inputType: String, videoURL: URL?, mode: String = "lite") {
        self.inputType = inputType
        self.videoURL = videoURL
        self.mode = mode
    }
    ```
    Add the inverse relationship:
    ```swift
    @Relationship(deleteRule: .cascade) var results: [ServeResult] = []
    ```
31. Create `App/Models/SwiftData/ServeResult.swift`:
    ```swift
    import Foundation
    import SwiftData

    @Model
    final class ServeResult {
        var id: UUID = UUID()
        var serveIndex: Int = 0
        var summary: String?
        @Relationship(deleteRule: .cascade) var cues: [CueRecord] = []
        var session: ServeSession?

        init(serveIndex: Int, summary: String?) {
            self.serveIndex = serveIndex
            self.summary = summary
        }
    }
    ```
32. Create `App/Models/SwiftData/CueRecord.swift`:
    ```swift
    import Foundation
    import SwiftData

    @Model
    final class CueRecord {
        var id: UUID = UUID()
        var ruleId: String = ""
        var phase: String = ""
        var message: String = ""
        var severity: String = ""
        var result: ServeResult?

        init(ruleId: String, phase: String, message: String, severity: String) {
            self.ruleId = ruleId
            self.phase = phase
            self.message = message
            self.severity = severity
        }
    }
    ```
33. Confirm `ServeResult` and `CueRecord` are added to the app's SwiftData `ModelContainer` schema
    list (find wherever `ServeSession.self`/`PhaseRecord.self` are currently registered — likely
    the app entry point's `.modelContainer(for:)` or an explicit `Schema([...])` — add both new
    types alongside them).
34. Create `MyServeCoachTests/ServeResultPersistenceTests.swift` (in-memory `ModelContainer`,
    matching however `PhaseRecord`/`ServeSession` are already tested if such a test exists —
    otherwise a fresh in-memory container): round-trip a `ServeSession(mode: "pro2d")` with 2
    `ServeResult`s each holding cues; fetch it back; assert `mode`, `results.count`,
    `results[0].cues.count`, and cascade-delete (deleting the session deletes its results and
    their cues).
35. Run `scripts/verify.sh ios` — confirm green.

## Group 7 — iOS: Assessment Results Screen + Persistence Wiring (surface: `ios`)

36. Create `App/ViewModels/AssessmentResultViewModel.swift`:
    ```swift
    import Foundation
    import Observation
    import SwiftData

    struct AssessmentServeDisplay: Identifiable {
        let id = UUID()
        let serveIndex: Int
        let summary: String?
        let cues: [Cue]  // pre-sorted: major before minor, then Kovacs phase order
    }

    @MainActor
    @Observable
    final class AssessmentResultViewModel {
        let serves: [AssessmentServeDisplay]
        let inputType: String
        private let videoURL: URL?

        var totalMajorCount: Int { serves.flatMap(\.cues).filter { $0.severity == "major" }.count }
        var totalMinorCount: Int { serves.flatMap(\.cues).filter { $0.severity == "minor" }.count }

        init(results: [AssessmentServeResult], inputType: String, videoURL: URL?) {
            self.inputType = inputType
            self.videoURL = videoURL
            let phaseOrder = ["start", "release", "trophy_pose", "racket_drop", "contact", "finish"]
            self.serves = results.map { result in
                let sorted = result.coaching.cues.sorted { a, b in
                    if a.severity != b.severity { return a.severity == "major" }
                    let ai = phaseOrder.firstIndex(of: a.phase) ?? phaseOrder.count
                    let bi = phaseOrder.firstIndex(of: b.phase) ?? phaseOrder.count
                    return ai < bi
                }
                return AssessmentServeDisplay(serveIndex: result.serveIndex, summary: result.coaching.summary, cues: sorted)
            }
        }

        func persist(to context: ModelContext) {
            let session = ServeSession(inputType: inputType, videoURL: videoURL, mode: "pro2d")
            for serve in serves {
                let result = ServeResult(serveIndex: serve.serveIndex, summary: serve.summary)
                result.cues = serve.cues.map {
                    CueRecord(ruleId: $0.ruleId, phase: $0.phase, message: $0.message, severity: $0.severity)
                }
                session.results.append(result)
            }
            context.insert(session)
        }
    }
    ```
37. Create `App/Views/AssessmentResultView.swift`:
    - Header: `"\(viewModel.serves.count) serve(s) analyzed"`, `"\(totalMajorCount) major ·
      \(totalMinorCount) minor"`.
    - One section per `AssessmentServeDisplay` (`"Serve \(serveIndex + 1)"`), listing each cue's
      `message` with a severity-colored indicator (red for major, orange for minor — matching the
      existing `errorBanner`/`photoPermissionDeniedBanner` red/orange convention in
      `VideoSourceSelectionView`) and its `summary` if non-nil.
    - Empty-cues-across-all-serves case: show a positive "No major issues detected" state per
      serve (reuse each serve's own `summary`, which the backend already sets to that string when
      clean).
    - `.onAppear` (or `.task`, once): call `viewModel.persist(to: modelContext)` via
      `@Environment(\.modelContext)`.
    - A "Done" toolbar button dismissing back to `VideoSourceSelectionView` (mirrors
      `PhaseReviewView`'s cancellation-action pattern).
38. Wire navigation in `VideoSourceSelectionView.swift`:
    ```swift
    .navigationDestination(isPresented: $viewModel.navigateToAssessmentResults) {
        if let results = viewModel.assessmentResults {
            AssessmentResultView(
                viewModel: AssessmentResultViewModel(
                    results: results, inputType: viewModel.pendingInputType, videoURL: viewModel.pendingVideoURL
                ),
                onDone: { viewModel.dismissAssessmentResults() }
            )
        }
    }
    ```
    (Requires exposing `pendingInputType`/`pendingVideoURL` as `private(set)` rather than fully
    private on the view model, or constructing the `AssessmentResultViewModel` inside
    `runProPipeline` itself and storing *that* rather than the raw `[AssessmentServeResult]` —
    prefer the latter: store `assessmentResultViewModel: AssessmentResultViewModel?` instead of
    raw results, mirroring how `phaseReviewViewModel` is already stored for the Lite path.)
    Add `dismissAssessmentResults()` mirroring `dismissPhaseReview()`.
39. Create `MyServeCoachTests/AssessmentResultViewModelTests.swift`:
    - `test_sortsCuesMajorBeforeMinorWithinPhaseOrder`.
    - `test_totalCountsSumAcrossAllServes`.
    - `test_persistCreatesServeSessionWithModePro2dAndCascadedResults` (in-memory `ModelContext`,
      assert `session.mode == "pro2d"`, `session.results.count`, cue field round-trip).
40. Run `scripts/verify.sh ios` — confirm green.

## Group 8 — iOS: History Screen Integration (surface: `ios`)

41. In `App/Views/SessionHistoryRowView.swift`, branch on `session.mode`:
    ```swift
    private var isProSession: Bool { session.mode != "lite" }

    private var proSubtitle: String {
        let cueCount = session.results.flatMap(\.cues).count
        return "\(session.results.count) serve(s) · \(cueCount) cue(s)"
    }
    ```
    In `body`, when `isProSession`: render a "Pro 2D" `Text` badge (small, capsule background,
    matching the app's existing badge-less style — a simple `.font(.caption2.weight(.semibold))`
    capsule is sufficient, no new design system needed) in place of the phase thumbnail, and
    `proSubtitle` in place of `inputTypeBadge`. Lite rows (`session.mode == "lite"`) render exactly
    as today — no visual change.
42. In `App/Views/SessionHistoryView.swift`, branch the single `navigationDestination(for:
    ServeSession.self)` closure on `session.mode`:
    ```swift
    .navigationDestination(for: ServeSession.self) { session in
        if session.mode == "lite" {
            HistoryComparisonView(session: session)
        } else {
            AssessmentHistoryDetailView(session: session)
        }
    }
    ```
43. Create `App/Views/AssessmentHistoryDetailView.swift` — read-only, reuses
    `AssessmentResultViewModel`'s display types but is constructed directly from a `ServeSession`'s
    persisted `results`/`cues` (not from a fresh `[AssessmentServeResult]`, which no longer exists
    at this point):
    ```swift
    struct AssessmentHistoryDetailView: View {
        let session: ServeSession
        // Maps session.results (sorted by serveIndex) -> the same per-serve section layout as
        // AssessmentResultView, reading ServeResult/CueRecord directly instead of AssessmentServeResult.
        // No persist() call — this is a read-only replay of already-saved data.
    }
    ```
    (Implementer's choice whether to factor the shared section-rendering into a small reusable
    view used by both `AssessmentResultView` and this view — reasonable either way given the
    input types differ; avoid over-abstracting for a two-caller reuse if the mapping is trivial.)
44. Create `MyServeCoachTests/SessionHistoryRowViewModeTests.swift` or extend an existing
    view-level test file if one exists for `SessionHistoryRowView` — if the codebase has no
    existing SwiftUI-view-level tests for this file (thumbnail logic is a computed property, so a
    plain `Testing` unit test can exercise `proSubtitle`/`isProSession` without ViewInspector),
    write plain unit tests against those computed properties for a mock/in-memory `ServeSession`.
45. Run `scripts/verify.sh ios` — confirm green.

## Group 9 — Cross-Cutting Verification (surface: `both`)

46. Run `scripts/verify.sh backend` and `scripts/verify.sh ios` — both green.
47. Run `git diff --name-only develop...HEAD` and confirm none of `PhaseReviewView.swift`,
    `PoseAnalysisPipeline.swift`, `PoseEstimationService.swift`, `ServeSegmentationService.swift`,
    `PhaseGuesser.swift`, `ContentView.swift` appear in the list.
48. Confirm `VideoSourceSelectionViewModelTests.swift`'s pre-existing Lite-path test cases
    (zero-segments / success / failure / permission branches) still pass unmodified in assertion
    content — only the `selectedMode: .lite` explicitness from step 28 was added, no existing
    assertion changed.
49. Record in `validation.md` run notes: confirmation that a real Mac-hosted backend run (manual,
    outside pytest/xcodebuild) was smoke-tested — record backend startup command, one real device
    or simulator recording routed through Pro 2D mode end-to-end, and whether cues appeared as
    expected. If a real device/backend pairing isn't available at implementation time, record that
    explicitly as a known gap rather than silently skipping it.
