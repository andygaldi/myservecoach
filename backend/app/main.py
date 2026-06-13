from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from app.routers import analyze, reference_frames

app = FastAPI(title="MyServeCoach API")

app.mount("/static", StaticFiles(directory="static"), name="static")

app.include_router(analyze.router, prefix="/v1")
app.include_router(reference_frames.router)
