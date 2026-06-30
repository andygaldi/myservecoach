# Phase 8 — Reference Frame Backend & iOS Networking

## Scope

Pivot the FastAPI backend from a coaching rule engine to a reference frame API. The backend hosts one curated phase frame per serve phase (trophy pose, racket drop, contact point) sourced from high-quality servers. iOS fetches these frames via URLSession at the end of the manual phase review step — immediately after the user confirms their last phase frame.

Phase 9 will consume the fetched reference frames to build the side-by-side comparison screen. Phase 8 only delivers and validates the network contract; no comparison UI is built here.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Response format | JSON with image URLs | iOS fetches images independently; HTTP caching works normally; images can be swapped without changing the API contract |
| Reference frame content | Real curated frames | Ship with actual high-quality serve screenshots from day one; no placeholder pass needed |
| Frames per phase | One per phase | Single canonical reference keeps the Phase 9 comparison layout simple and unambiguous |
| Static file serving | FastAPI `StaticFiles` mount at `/static` | No separate file server needed; images live in `backend/static/reference_frames/` |

## API Contract

**Endpoint:** `GET /reference-frames`

**Response (HTTP 200):**
```json
{
  "reference_frames": {
    "trophy_pose": {
      "phase": "trophy_pose",
      "label": "Trophy Pose",
      "image_url": "http://<host>/static/reference_frames/trophy_pose.jpg"
    },
    "racket_drop": {
      "phase": "racket_drop",
      "label": "Racket Drop",
      "image_url": "http://<host>/static/reference_frames/racket_drop.jpg"
    },
    "contact": {
      "phase": "contact",
      "label": "Contact Point",
      "image_url": "http://<host>/static/reference_frames/contact.jpg"
    }
  }
}
```

The host in image URLs is dynamic — the backend must construct URLs using the incoming request's base URL so they resolve correctly regardless of whether the app is hitting localhost or a future remote server.

## iOS Integration Point

After the user confirms the third (final) phase frame in the Phase 7 manual selection UI, the app calls `ReferenceFrameService.fetchReferenceFrames()`. On success the fetched frames are passed forward (stub/placeholder for Phase 9). On failure a dismissable error alert is shown with a retry option.

## Context

- Phase 7 is complete: the user's confirmed phase frames are the canonical result for a session.
- The coaching rule engine (`rules.json`, `phases.py`) remains in the backend codebase but is not invoked by Phase 8 or any Lite MVP flow.
- Network is required; no offline fallback in MVP (per tech-stack decision).
- Backend runs locally during development; iOS simulator/device hits `http://localhost:8000`.

## Out of Scope

- Displaying the reference frames (Phase 9)
- Persisting reference frame URLs to SwiftData (Phase 10)
- Multiple reference frames per phase or a user-selectable carousel
- Authentication or API keys
- CDN or cloud hosting
