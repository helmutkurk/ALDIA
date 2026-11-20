from io import BytesIO
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from PIL import Image
from test_reports import submit
from test_v02 import OPERATOR, enable_staff
from test_v02_edges import seed

from app.models import Report

BBOX = "-91,14,-90,15"


def test_thumbnail_is_small_cached_and_clean(client: TestClient) -> None:
    report = submit(client).json()
    url = f"/api/reports/{report['id']}/thumbnail"
    storage = client.app.state.services.storage
    cached = storage.thumbnail_path(report["id"])
    assert not cached.exists()
    response = client.get(url)
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/jpeg"
    assert response.headers["cache-control"] == "public, max-age=86400"
    image = Image.open(BytesIO(response.content))
    assert image.format == "JPEG" and max(image.size) <= 320
    assert image.size == (320, 240)
    assert not image.getexif()
    assert cached.is_file() and cached.parent == storage.root
    assert cached.read_bytes() == response.content
    cached.write_bytes(response.content + b"")  # unchanged content, served from cache
    mtime = cached.stat().st_mtime_ns
    assert client.get(url).content == response.content
    assert cached.stat().st_mtime_ns == mtime
    assert client.get(report["photo_url"]).status_code == 200


def test_thumbnail_hidden_invalid_and_missing(client: TestClient) -> None:
    enable_staff(client)
    report = submit(client).json()
    with client.app.state.services.database.sessions() as session:
        row = session.get(Report, UUID(report["id"]))
        row.state = "oculto"
        session.commit()
    url = f"/api/reports/{report['id']}/thumbnail"
    assert client.get(url).status_code == 404
    assert client.get(url, headers=OPERATOR).status_code == 200
    assert client.get("/api/reports/not-a-uuid/thumbnail").status_code == 422
    assert client.get(f"/api/reports/{uuid4()}/thumbnail").status_code == 404
    assert client.get("/api/reports/..%2f..%2fetc%2fpasswd/thumbnail").status_code in {
        404,
        422,
    }


def test_clusters_split_a_city_at_city_zoom(client: TestClient) -> None:
    # 60 reports: six neighbourhoods about 700 m apart, ten reports each within 80 m.
    for hood in range(6):
        for index in range(10):
            seed(
                client,
                lat=14.60 + (hood // 3) * 0.007 + (index // 5) * 0.0004,
                lon=-90.52 + (hood % 3) * 0.007 + (index % 5) * 0.00016,
            )
    clusters = {}
    for zoom in (12, 14, 15):
        body = client.get(f"/api/reports/clusters?bbox={BBOX}&zoom={zoom}").json()
        assert body["total"] == 60
        assert sum(c["count"] for c in body["clusters"]) == 60
        clusters[zoom] = body["clusters"]
    assert 3 <= len(clusters[12]) < 60
    assert 6 <= len(clusters[14]) < 60
    assert len(clusters[15]) == 60
    assert all(c["count"] == 1 for c in clusters[15])
