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
async def test_reference_frames_has_three_phase_keys(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    assert set(data["reference_frames"].keys()) == {"trophy_pose", "racket_drop", "contact"}


@pytest.mark.asyncio
async def test_reference_frames_entries_have_required_fields(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    for entry in data["reference_frames"].values():
        assert "phase" in entry
        assert "label" in entry
        assert "image_url" in entry


@pytest.mark.asyncio
async def test_reference_frames_image_url_filenames(transport):
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        data = (await client.get("/reference-frames")).json()
    frames = data["reference_frames"]
    assert frames["trophy_pose"]["image_url"].endswith("trophy_pose.jpg")
    assert frames["racket_drop"]["image_url"].endswith("racket_drop.jpg")
    assert frames["contact"]["image_url"].endswith("contact.jpg")
