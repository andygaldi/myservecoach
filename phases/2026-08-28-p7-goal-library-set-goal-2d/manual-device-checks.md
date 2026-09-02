# P7 — Manual Real-Device Checks (closes validation.md's hard gate)

Run these on a physical iPhone (Simulator has no camera). This is the last item blocking
`/merge` for `phases/2026-08-28-p7-goal-library-set-goal-2d`.

## Setup

1. Start the backend on your Mac:
   `cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
   (device and Mac must be on the same LAN; note which `DETECTION_MODEL_DEVICE` you're running
   with — `cpu` or `mps` — you'll need to record it).
2. Confirm the app's `BackendConfig.baseURL` points at your Mac's LAN IP, not `localhost`.
3. Build & run on the device from Xcode (`Cmd+R`, physical device selected, not a simulator).
4. Navigate: Pro 2D → Set Goal → pick any goal → start a session.

## Check A — chunk rotation (validation.md Group 4)

Record several minutes, spanning many 2s chunk boundaries. Watch Xcode's console output
confirming `onChunkFinalized` fires repeatedly with valid, increasing files, and the app stays
responsive throughout — no crash, no hang.

**Record:** pass/fail, anything unusual observed.

## Check B — audio quality (validation.md Group 6)

Hit several real serves. For each one, confirm:
- the spoken cue is audible over the device speaker at normal volume
- it's timed close enough after the serve to be useful ("stay focused on the court between
  serves")
- the cue text is spoken clearly, not garbled or cut off

**Record:** pass/fail, anything unusual observed.

## Check C — latency measurement (validation.md Group 8 — the hard gate)

For each serve: note wall-clock time at contact (stopwatch or eyeballed) and the time the cue is
spoken. Compute contact→cue seconds per serve.

**Bar: median ≤5s, max ≤8s.**

**Record:** the per-serve numbers, the median and max, and which pipeline/device config was used
(`fused/cpu` or `fused/mps` — from the backend's `DETECTION_MODEL_DEVICE` env var).

## Check D — end-to-end (validation.md Group 8)

Stop the session. Confirm:
- the summary screen shows the correct pass/attempt tally
- tapping Save works
- the session reopens correctly from History (same goal, same attempts, same pass/fail + spoken
  cues)

**Record:** pass/fail, anything unusual observed.

## After running these

Report back (in a future session, after clearing context, that's fine — this file has everything
needed) the outcomes of A–D, including the Check C numbers and pipeline config. Ask to have them
written into `phases/2026-08-28-p7-goal-library-set-goal-2d/validation.md`'s Run Notes — that
closes the phase's last hard gate before `/merge`.
