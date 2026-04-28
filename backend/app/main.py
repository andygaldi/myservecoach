from fastapi import FastAPI
from app.routers import analyze

app = FastAPI(title="MyServeCoach API")

app.include_router(analyze.router)
