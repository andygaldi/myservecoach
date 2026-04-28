# Mission

## Product

**MyServeCoach** — instant serve analysis for competitive tennis players.

## Problem

Club-level players (league competitors, tournament regulars) rarely have access to a coach during practice. Serve technique degrades, flaws go unnoticed, and feedback only arrives at scheduled lessons — too infrequently to drive real improvement.

## Solution

MyServeCoach lets a player record their serve on an iPhone and receive specific, actionable coaching cues within seconds. No coach needed on court. Free, with no subscription or in-app purchase. No waiting.

## User Workflows

### Assessment
The user provides one continuous video clip of themselves hitting several serves back-to-back — either by recording live with the iPhone camera or by selecting an existing video from their Photos library. When recording live, a brief pose confidence check is shown first: the camera displays a real-time skeleton overlay and warns the user if joint confidence is low, so they can adjust their position or lighting before committing to a full recording. The app then automatically detects and segments the individual serves within the clip, analyzes all of them, and returns a prioritized list of coaching cues covering technique, timing, and mechanics — a holistic read on where to improve. Results are saved to session history for later review.

### Set Goal
Before recording, the user selects a single technique focus from a curated goal catalog (e.g., "pronation through contact", "trophy pose elbow height"). The goal catalog is a fixed list built into the app, designed to be extensible in future versions. The app records continuously — the camera runs uninterrupted and automatically detects each serve as it happens. After each detected serve it speaks a short audible cue — "good" or a one-line correction — so the player stays focused on the court rather than the screen. The session runs until the user taps "End Session"; the video is then discarded and only per-serve keypoints and pass/fail results are saved. Designed for deliberate-practice drills where fast, eyes-free feedback is essential.

## Target User

Club-level competitive tennis player who:
- Competes in USTA leagues or local tournaments
- Practices 2–4× per week, often without a coach present
- Wants data-driven, specific feedback — not generic tips
- Is comfortable with iOS apps and expects a polished experience

## Core Value Proposition

**Specific, actionable coaching cues seconds after you record.** Not a score, not a chart — a short list of what to fix and why, grounded in biomechanics (trophy pose, racket drop, contact point). And for focused drills, instant audible feedback after every single serve so you never have to break your rhythm.

## Future Differentiators (post-MVP)

- Natural-language coaching powered by LLM (Claude API) for richer, conversational feedback
- Visual pose skeleton overlay on keyframe thumbnails
- Longitudinal serve history and trend analysis

## Business Model

Free app, no monetization. No subscription, no in-app purchase, no ads.

## Out of Scope (MVP)

- Social features, sharing, or leaderboards
- Multi-sport or non-serve stroke analysis
- Web or Android clients
- Cloud video storage
- User-defined custom goals (goal catalog is fixed; extensibility designed in, not exposed)
