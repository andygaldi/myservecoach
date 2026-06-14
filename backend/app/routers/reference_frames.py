from pathlib import Path

from fastapi import APIRouter, Request

router = APIRouter()

_STATIC_DIR = Path(__file__).parent.parent.parent / "static" / "reference_frames"

_PHASES = [
    ("trophy_pose", "Trophy Pose"),
    ("racket_drop", "Racket Drop"),
    ("contact", "Contact Point"),
]


def _phase_files(phase: str) -> list[str]:
    """Return sorted filenames for a phase: primary first, then _2, _3, …"""
    return sorted(
        f.name
        for f in _STATIC_DIR.iterdir()
        if f.name == f"{phase}.jpg"
        or (f.name.startswith(f"{phase}_") and f.name.endswith(".jpg"))
    )


@router.get("/reference-frames")
async def get_reference_frames(request: Request) -> dict:
    base = str(request.base_url).rstrip("/")
    frames: dict = {}
    for phase, label in _PHASES:
        frames[phase] = [
            {
                "phase": phase,
                "label": label,
                "image_url": f"{base}/static/reference_frames/{filename}",
            }
            for filename in _phase_files(phase)
        ]
    return {"reference_frames": frames}
