import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app


@pytest.fixture
def transport():
    return ASGITransport(app=app)


@pytest.mark.asyncio
async def test_reference_frames_returns_200(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/reference-frames")
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_reference_frames_has_three_phases(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    phases = {f["phase"] for f in data["reference_frames"]}
    assert phases == {"trophy_pose", "racket_drop", "contact"}


@pytest.mark.asyncio
async def test_reference_frames_are_in_serve_order(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    phases = [f["phase"] for f in data["reference_frames"]]
    assert phases == ["trophy_pose", "racket_drop", "contact"]


@pytest.mark.asyncio
async def test_reference_frames_entries_have_required_fields(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    for entry in data["reference_frames"]:
        assert "phase" in entry
        assert "label" in entry
        assert "image_url" in entry


@pytest.mark.asyncio
async def test_reference_frames_image_urls(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    by_phase = {f["phase"]: f for f in data["reference_frames"]}
    assert by_phase["trophy_pose"]["image_url"] == "http://test/static/reference_frames/trophy_pose.jpg"
    assert by_phase["racket_drop"]["image_url"] == "http://test/static/reference_frames/racket_drop.jpg"
    assert by_phase["contact"]["image_url"] == "http://test/static/reference_frames/contact.jpg"
