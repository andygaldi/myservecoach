# Phase 3 — Backend Scaffold: Plan

## 1. Project Scaffolding

- Create `backend/` directory at monorepo root
- Add `backend/requirements.txt`: `fastapi`, `uvicorn[standard]`, `pydantic`, `pytest`, `httpx`
- Add `backend/.gitignore`: `__pycache__/`, `*.pyc`, `.env`, `.venv/`
- Add `backend/README.md` with one-liner on how to run via Docker Compose

## 2. FastAPI App Skeleton

- `backend/app/__init__.py`
- `backend/app/main.py`: create the FastAPI `app` instance, register routers
- `backend/app/routers/__init__.py`
- `backend/app/routers/analyze.py`: placeholder router module for `POST /analyze`

## 3. Pydantic Models

- `backend/app/models.py`:
  - `Keypoint`: `x: float`, `y: float`, `confidence: float`
  - `Frame`: `timestamp: float`, `keypoints: dict[str, Keypoint]`
  - `AnalyzeRequest`: `frames: list[Frame]` (min length 1)
  - `ServePhase`: enum — `trophy_pose`, `racket_drop`, `contact`
  - `Severity`: enum — `major`, `minor`
  - `Cue`: `phase: ServePhase`, `message: str`, `severity: Severity`
  - `AnalyzeResponse`: `cues: list[Cue]`

## 4. POST /analyze Endpoint

- Implement `POST /analyze` in `routers/analyze.py`
- Accept `AnalyzeRequest`, return `AnalyzeResponse`
- Return two hardcoded `Cue` objects (one `major`, one `minor`) regardless of input
- Wire router into `main.py`

## 5. Docker Compose Setup

- `backend/Dockerfile`: Python 3.12 slim base, copy `requirements.txt`, `pip install`, copy app, expose port 8000, `CMD uvicorn app.main:app --host 0.0.0.0 --port 8000`
- `docker-compose.yml` at monorepo root: single `backend` service, build from `./backend`, ports `8000:8000`, `--reload` mount for local dev

## 6. Tests

- `backend/tests/__init__.py`
- `backend/tests/test_analyze.py` using `httpx.AsyncClient` + `pytest-asyncio`:
  - Valid payload with one frame → 200, response matches `AnalyzeResponse` schema
  - Empty `frames` list → 422
  - Missing `keypoints` field on a frame → 422
  - Unknown extra field on keypoint → ignored (default Pydantic behavior, assert 200)

## 7. Smoke-Test Verification

- Confirm `docker compose up` starts cleanly with no import errors
- `curl -X POST http://localhost:8000/analyze` with sample payload returns the hardcoded cues
- Document the curl command in `backend/README.md` for iOS integration reference
