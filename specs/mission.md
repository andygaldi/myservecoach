# Mission

## Product

**MyServeCoach** — visual serve comparison for competitive tennis players.

## Problem

Club-level players rarely have access to a coach during practice. Serve technique degrades, flaws go unnoticed, and self-assessment is hard because most players have never seen how elite servers look at the same critical moments in the motion.

## Solution

MyServeCoach lets a player record their serve on an iPhone and immediately compare their form to reference serves from high-quality players — frame by frame, at the same critical moments. No coaching expertise required; the reference frames speak for themselves. In its more capable modes, the app also automatically detects serve phases and racket/ball position and returns rule-based coaching cues.

The product has **three permanent, user-selectable capture modes** (see "Capture Modes" below). **Lite mode is not an MVP that a future version supersedes — it is one of three coequal, permanently supported modes.** A player who only ever brings their phone and a tripod to the court gets the full Lite experience forever; Pro modes are an additive tier for players willing to bring processing hardware, not a replacement.

## Capture Modes

| | Lite | Pro 2D | Pro 3D |
|---|---|---|---|
| **Processing location** | On-device (Apple Vision) | Off-device (Jetson Orin Nano) | Off-device (Jetson Orin Nano) |
| **Hardware required** | iPhone + tripod | iPhone + tripod + Jetson | iPhone + tripod + Jetson + 2 cameras |
| **Serve phase detection** | On-device guess, user manually corrects | Automatic (pose + racket/ball signals) | Automatic (3D pose + racket/ball signals) |
| **Coaching** | None — visual comparison only | Rule-based cues, Set Goal mode | Rule-based cues (3D-calibrated), Set Goal mode |
| **Status** | Permanent, built (Phases 1–11) | Planned (roadmap P1–P6) | Planned (roadmap P7–P11) |

**Isolation rule:** Off-device pose, object-detection, and coaching code is additive and mode-gated. It must never run inside, or replace, the Lite path. Lite's only backend dependency is `GET /reference-frames` (a static reference-frame library) — it never calls `/v1/pose` or `/v1/analyze`. Pro 2D and Pro 3D are the only consumers of the off-device endpoints. See `specs/offdevice-pipeline.md` for the full off-device architecture and this same rule restated there.

## User Workflows

### Serve Comparison (Lite mode)

The user records a serve clip (or selects one from their Photos library) with their iPhone positioned to the open side (perpendicular to the serve direction). The app runs on-device pose estimation to produce an initial guess at the three key serve phases — trophy pose, racket drop, and contact point. The user reviews the guessed frames and can scrub through the video to manually correct any phase frame that landed in the wrong spot. Once confirmed, the app fetches reference frames from the backend — curated frames from high-quality servers at the same three phases — and presents a side-by-side comparison. Results are saved to session history for later review.

## Target User

Club-level competitive tennis player who:
- Competes in USTA leagues or local tournaments
- Practices 2–4× per week, often without a coach present
- Wants a concrete visual reference — not generic tips
- Is comfortable with iOS apps and expects a polished experience

## Core Value Proposition

**See how your serve stacks up against high-quality players at every critical moment.** Frame by frame: your trophy pose next to theirs, your racket drop next to theirs, your contact point next to theirs. No coach required, no expertise assumed.

## Pro Modes (Planned)

The following workflows are planned for Pro 2D and Pro 3D mode. They require significantly better pose estimation than Apple Vision currently provides — specifically, reliable background removal and racket-object detection so that automatic serve segmentation works consistently across real-world court environments. They are additive to Lite mode, not a replacement for it.

### Assessment (Pro 2D / Pro 3D)

One continuous clip of several back-to-back serves. The app automatically detects and segments each serve, analyzes all of them, and returns a prioritized list of specific, actionable coaching cues covering technique, timing, and mechanics — no manual frame selection required.

### Set Goal (Pro 2D / Pro 3D)

Continuous recording session focused on a single technique goal (e.g., "trophy pose elbow height"). After each auto-detected serve, the app speaks an audible pass/fail cue so the player stays focused on the court. Designed for deliberate-practice drills.

## Future Differentiators

- **Pro 2D and Pro 3D modes, off-device pose (Mac dev host first, Jetson for court portability)**: The current bottleneck is on-device Vision's inability to handle real court backgrounds and racket detection reliably. Pro modes run pose estimation off-device — developed on the Mac development host (the Mac already serves as the Lite backend, so development starts immediately with no new hardware) and deployed to a Jetson Orin Nano for on-court use. **Pro 2D** (iPhone only, 2D angles) ships first with the complete coaching experience; **Pro 3D** (iPhone + two USB webcams, true 3D angles via stereo triangulation) extends it with higher biomechanical precision. Both are selected explicitly by the user at session setup, alongside Lite — see "Capture Modes" above. Strong 2D pose models (RTMPose/YOLO via ONNX Runtime) and a YOLO object detector (racket + ball) enable background-robust segmentation across both Pro modes. The final step migrates the proven pipeline to a Jetson Orin Nano for untethered, battery-powered on-court portability. See `specs/offdevice-pipeline.md` for the full architecture.
- Natural-language coaching powered by LLM (Claude API) for richer, conversational feedback
- Visual pose skeleton overlay on keyframe thumbnails
- Longitudinal serve history and trend analysis
- Serve-type awareness: reference frames and future coaching cues tailored to flat, slice, or kick serve
- Six-frame serve analysis based on the Kovacs biomechanical model — Lite mode covers stages 3, 4, and 6 (Loading/trophy pose, Cocking/racket drop, Contact); Pro modes add Start (1), Release (2), and Finish (8) for the complete six-frame model. Stages 5 (Acceleration) and 7 (Deceleration) are continuous motion phases, not discrete frames. This is built directly into Pro Phase P3 serve segmentation.
- Apple Watch integration: remote start/stop from the wrist; accelerometer data for wrist pronation
- External racket sensor support: Bluetooth IMU for racket-head speed and swing-path angle

## Business Model

Free app, no monetization. No subscription, no in-app purchase, no ads.

## Out of Scope (Lite Mode)

- Automated coaching cues or rule-based serve analysis
- Real-time per-serve feedback or audible cues during drills
- Pose skeleton overlay on captured frames
- Pre-recording live pose confidence check
- Social features, sharing, or leaderboards
- Multi-sport or non-serve stroke analysis
- Web or Android clients
- Cloud video storage
- Additional recording angles (behind-server, closed side) — Lite mode requires open-side placement only
