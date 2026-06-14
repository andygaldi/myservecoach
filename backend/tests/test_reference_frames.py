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
    assert set(data["reference_frames"].keys()) == {"trophy_pose", "racket_drop", "contact"}


@pytest.mark.asyncio
async def test_reference_frames_are_in_serve_order(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    assert list(data["reference_frames"].keys()) == ["trophy_pose", "racket_drop", "contact"]


@pytest.mark.asyncio
async def test_reference_frames_entries_have_required_fields(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    for phase_frames in data["reference_frames"].values():
        assert isinstance(phase_frames, list)
        assert len(phase_frames) >= 1
        for entry in phase_frames:
            assert "phase" in entry
            assert "label" in entry
            assert "image_url" in entry


@pytest.mark.asyncio
async def test_reference_frames_image_urls(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    rf = data["reference_frames"]
    assert rf["trophy_pose"][0]["image_url"] == "http://test/static/reference_frames/trophy_pose.jpg"
    assert rf["racket_drop"][0]["image_url"] == "http://test/static/reference_frames/racket_drop.jpg"
    assert rf["contact"][0]["image_url"] == "http://test/static/reference_frames/contact.jpg"
