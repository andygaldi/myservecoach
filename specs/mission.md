# Mission

## Product

**MyServeCoach** — visual serve comparison for competitive tennis players.

## Problem

Club-level players rarely have access to a coach during practice. Serve technique degrades, flaws go unnoticed, and self-assessment is hard because most players have never seen how elite servers look at the same critical moments in the motion.

## Solution

MyServeCoach lets a player record their serve on an iPhone and immediately compare their form to reference serves from high-quality players — frame by frame, at the same critical moments. The app automatically identifies the key phases of the serve (trophy pose, racket drop, contact point) using on-device pose estimation, then lets the user review and correct the detected frames before showing a side-by-side visual comparison. No coaching expertise required; the reference frames speak for themselves.

This is the **Lite Version** of the app — the initial MVP optimized for what current on-device technology can deliver reliably. A future **Pro Version** will add fully automated coaching cues and real-time drill feedback leveraging custom-built off-device pose estimation.

## User Workflows

### Serve Comparison (Lite Version — MVP)

The user records a serve clip (or selects one from their Photos library) with their iPhone positioned to the open side (perpendicular to the serve direction). The app runs on-device pose estimation to produce an initial guess at the three key serve phases — trophy pose, racket drop, and contact point. The user reviews the guessed frames and can scrub through the video to manually correct any phase frame that landed in the wrong spot. Once confirmed, the app fetches reference frames from the backend — curated frames from high-quality servers at the same three phases — and presents a side-by-side comparison. Results are saved to session history for later review.

## Target User

Club-level competitive tennis player who:
- Competes in USTA leagues or local tournaments
- Practices 2–4× per week, often without a coach present
- Wants a concrete visual reference — not generic tips
- Is comfortable with iOS apps and expects a polished experience

## Core Value Proposition

**See how your serve stacks up against high-quality players at every critical moment.** Frame by frame: your trophy pose next to theirs, your racket drop next to theirs, your contact point next to theirs. No coach required, no expertise assumed.

## Pro Version (Deferred)

The following workflows are planned for a future Pro Version. They require significantly better pose estimation than Apple Vision currently provides — specifically, reliable background removal and racket-object detection so that automatic serve segmentation works consistently across real-world court environments.

### Assessment (Pro)

One continuous clip of several back-to-back serves. The app automatically detects and segments each serve, analyzes all of them, and returns a prioritized list of specific, actionable coaching cues covering technique, timing, and mechanics — no manual frame selection required.

### Set Goal (Pro)

Continuous recording session focused on a single technique goal (e.g., "trophy pose elbow height"). After each auto-detected serve, the app speaks an audible pass/fail cue so the player stays focused on the court. Designed for deliberate-practice drills.

## Future Differentiators

- **Pro Version — off-device pose estimation via Raspberry Pi**: The current bottleneck is on-device Vision's inability to handle real court backgrounds and racket detection reliably. The plan is to run pose estimation off-device on a Raspberry Pi connected to the iPhone over a local network. The Pi doubles as the API server (replacing a remote cloud backend), eliminating latency to the internet and keeping all data local to the court. It also provides a natural attachment point for a second camera, enabling simultaneous multi-angle capture and true 3D pose estimation by triangulating joint positions across views — meaningfully improving toss height/lateral position accuracy and unlocking the full Assessment and Set Goal workflows.
- Natural-language coaching powered by LLM (Claude API) for richer, conversational feedback
- Visual pose skeleton overlay on keyframe thumbnails
- Longitudinal serve history and trend analysis
- Serve-type awareness: reference frames and future coaching cues tailored to flat, slice, or kick serve
- Apple Watch integration: remote start/stop from the wrist; accelerometer data for wrist pronation
- External racket sensor support: Bluetooth IMU for racket-head speed and swing-path angle

## Business Model

Free app, no monetization. No subscription, no in-app purchase, no ads.

## Out of Scope (Lite MVP)

- Automated coaching cues or rule-based serve analysis
- Real-time per-serve feedback or audible cues during drills
- Pose skeleton overlay on captured frames
- Pre-recording live pose confidence check
- Social features, sharing, or leaderboards
- Multi-sport or non-serve stroke analysis
- Web or Android clients
- Cloud video storage
- Additional recording angles (behind-server, closed side) — MVP requires open-side placement only
