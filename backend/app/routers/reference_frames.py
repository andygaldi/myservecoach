from fastapi import APIRouter, Request

router = APIRouter()

_PHASES = [
    ("trophy_pose", "Trophy Pose", "trophy_pose.jpg"),
    ("racket_drop", "Racket Drop", "racket_drop.jpg"),
    ("contact", "Contact Point", "contact.jpg"),
]


@router.get("/reference-frames")
async def get_reference_frames(request: Request) -> dict:
    base = str(request.base_url).rstrip("/")
    frames = {
        phase: {
            "phase": phase,
            "label": label,
            "image_url": f"{base}/static/reference_frames/{filename}",
        }
        for phase, label, filename in _PHASES
    }
    return {"reference_frames": frames}
