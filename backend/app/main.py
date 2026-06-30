from pathlib import Path
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from app.routers import analyze, reference_frames

app = FastAPI(title="MyServeCoach API")

_STATIC_DIR = Path(__file__).parent.parent / "static"
app.mount("/static", StaticFiles(directory=_STATIC_DIR), name="static")

app.include_router(analyze.router, prefix="/v1")
app.include_router(reference_frames.router)
