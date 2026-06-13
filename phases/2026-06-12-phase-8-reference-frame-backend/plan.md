# Phase 8 — Plan

## Group 1 — Reference Frame Image Assets

1. Add curated reference frame images to `backend/static/reference_frames/`:
   - `trophy_pose.jpg` — high-quality server at trophy pose (max external rotation, racket pointed down)
   - `racket_drop.jpg` — racket drop / max external rotation transition
   - `contact.jpg` — ball contact point
2. Verify images are reasonable resolution for mobile comparison (recommend ~800×600px, ≤200 KB each).

## Group 2 — Backend Static File Serving

3. Mount `backend/static/` as a FastAPI `StaticFiles` instance at the `/static` path prefix.
4. Confirm a raw HTTP GET to `http://localhost:8000/static/reference_frames/trophy_pose.jpg` returns the image (manual curl or browser check).

## Group 3 — GET /reference-frames Endpoint

5. Implement `GET /reference-frames` in `backend/main.py` (or a dedicated router):
   - Build `image_url` values dynamically from `request.base_url` so they resolve on any host.
   - Return the three-phase JSON structure defined in `requirements.md`.
6. Write pytest tests in `backend/tests/test_reference_frames.py`:
   - HTTP 200 response.
   - Response contains exactly three phase keys: `trophy_pose`, `racket_drop`, `contact`.
   - Each entry has `phase`, `label`, and `image_url` fields.
   - Each `image_url` ends with the expected filename.
7. Run `pytest` and confirm all tests pass.

## Group 4 — iOS: ReferenceFrame Model & Service

8. Define `ReferenceFrame` and `ReferenceFrameLibrary` Codable models in `App/Models/`:
   ```swift
   struct ReferenceFrame: Codable {
       let phase: String
       let label: String
       let imageURL: URL

       enum CodingKeys: String, CodingKey {
           case phase, label
           case imageURL = "image_url"
       }
   }

   struct ReferenceFrameLibrary: Codable {
       let referenceFrames: [String: ReferenceFrame]

       enum CodingKeys: String, CodingKey {
           case referenceFrames = "reference_frames"
       }
   }
   ```
9. Implement `ReferenceFrameService` in `App/Services/` with a single async method:
   ```swift
   func fetchReferenceFrames() async throws -> ReferenceFrameLibrary
   ```
   Uses `URLSession.shared.data(from:)` and `JSONDecoder`. Base URL configurable via a constant (`BackendConfig.baseURL`).

## Group 5 — iOS: Wire Into Phase Review Flow

10. In the Phase 7 view model (end of phase confirmation), inject `ReferenceFrameService` and call `fetchReferenceFrames()` after the user confirms the last phase frame.
11. Hold the result in a `@State` / `@Published` property for Phase 9 to consume — log fetched URLs to the console for now.
12. On fetch failure, set an error state that triggers a dismissable alert: "Could not load reference frames. Check your connection and try again." with a Retry button that re-fires the fetch.

## Group 6 — Integration Smoke Test

13. Start the FastAPI backend locally (`uvicorn backend.main:app --reload`).
14. Build and run the iOS app on device or simulator (with backend reachable).
15. Complete the full flow: record/import → pose estimation → phase review → confirm all three frames.
16. Confirm in Xcode console: fetched reference frame URLs printed, images resolve (200) when opened in Safari.
17. Kill the backend and repeat: confirm the error alert appears and the Retry button re-fires the fetch.
