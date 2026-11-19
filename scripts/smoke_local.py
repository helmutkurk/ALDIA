"""Real curl assertions for the local stack; synthetic images and no secret output."""

import csv
import json
import os
import secrets
import subprocess
import tempfile
from datetime import UTC, datetime
from io import StringIO
from pathlib import Path
from uuid import uuid4

from PIL import Image, ImageDraw
from PIL.TiffImagePlugin import IFDRational

ROOT = Path(__file__).resolve().parents[1]
API = "http://127.0.0.1:8000/api"


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def run(directory):
    token = os.environ.get("STAFF_TOKEN")
    check(
        token and len(token) >= 32, "Run make dev-all SMOKE=1 to inherit STAFF_TOKEN."
    )
    calls = 0

    def request(
        name, url, expected=200, *, method="GET", headers=(), data=None, form=()
    ):
        nonlocal calls
        calls += 1
        output = directory / f"{calls:02d}-{name}.body"
        response_headers = output.with_suffix(".headers")
        command = [
            "curl",
            "--noproxy",
            "*",
            "--silent",
            "--show-error",
            "--max-time",
            "20",
            "--request",
            method,
            "--output",
            str(output),
            "--dump-header",
            str(response_headers),
            "--write-out",
            "%{http_code}",
        ]
        # Send credentials on stdin, never in argv, logs or an on-disk header file.
        if headers:
            command += ["--header", "@-"]
        if data is not None:
            command += [
                "--header",
                "Content-Type: application/json",
                "--data",
                json.dumps(data),
            ]
        for field in form:
            command += ["--form", field]
        command.append(url)
        result = subprocess.run(
            command,
            input="\n".join(headers) + "\n",
            text=True,
            capture_output=True,
            check=True,
        )
        check(
            result.stdout == str(expected),
            f"{name}: expected HTTP {expected}, got {result.stdout}",
        )
        print(f"PASS {name}: HTTP {expected}", flush=True)
        return output.read_bytes(), response_headers.read_text()

    def get(name, path, **kwargs):
        body, _ = request(name, API + path, **kwargs)
        return json.loads(body)

    for name, url in (
        ("verifier-health", "http://127.0.0.1:8001/health"),
        ("api-health", API + "/health"),
        ("portal-proxy-health", "http://127.0.0.1:5173/api/health"),
    ):
        body, _ = request(name, url)
        check(json.loads(body)["status"] == "ok", f"{name}: unhealthy body")
    body, _ = request("portal-html", "http://127.0.0.1:5173/")
    check(
        b'id="map"' in body and b'id="panel"' in body,
        "Portal HTML missing map/list roots",
    )
    categories = get("categories", "/categories")
    check(
        len(categories) == 6 and any(c["id"] == "pothole" for c in categories),
        "Category mismatch",
    )
    before = get("list-before", "/reports?include_old=true&limit=100")

    # A new random spatial pattern makes repeated runs distinct to the real dHash check.
    image = Image.new("RGB", (1280, 960), "gray")
    draw = ImageDraw.Draw(image)
    for row in range(8):
        for column in range(9):
            shade = secrets.randbelow(256)
            draw.rectangle(
                (column * 143, row * 120, (column + 1) * 143, (row + 1) * 120),
                fill=(shade, shade, shade),
            )
    draw.text((20, 20), "ALDIA - PRUEBA SINTETICA", fill="red")
    exif = Image.Exif()
    exif[0x010E] = "Synthetic local smoke test"
    exif[0x8825] = {
        1: "N",
        2: (IFDRational(14), IFDRational(38), IFDRational(564, 100)),
        3: "W",
        4: (IFDRational(90), IFDRational(30), IFDRational(2484, 100)),
    }
    source = directory / "source.jpg"
    image.save(source, "JPEG", quality=92, exif=exif)
    with Image.open(source) as photo:
        check(
            photo.size == (1280, 960) and photo.format == "JPEG", "Invalid source JPEG"
        )
        check(photo.getexif().get_ifd(0x8825).get(2), "Source GPS missing")
    print("PASS synthetic source: 1280x960 JPEG with EXIF GPS", flush=True)

    key = str(uuid4())
    # Give each run its own point so old smoke reports cannot fill the nearby top 10.
    latitude = 14.6349 + secrets.randbelow(1_000_000) / 1_000_000_000
    longitude = -90.5069 + secrets.randbelow(1_000_000) / 1_000_000_000
    fields = (
        f"photo=@{source};type=image/jpeg",
        "category=pothole",
        f"latitude={latitude}",
        f"longitude={longitude}",
        f"captured_at={datetime.now(UTC).isoformat()}",
        "note=[smoke] Prueba sintética local",
    )
    created = get(
        "create",
        "/reports",
        expected=201,
        method="POST",
        headers=(f"Idempotency-Key: {key}",),
        form=fields,
    )
    check(
        created["state"] == "nuevo" and created["status"] == "verified",
        "Report was not verified",
    )
    verification = created["verification"]
    check(
        verification["mode"] == "stub" and verification["passed"],
        "Verifier result mismatch",
    )
    check(
        len(verification["checks"]) == 5
        and all(c["passed"] for c in verification["checks"]),
        "Verification checks did not all pass",
    )
    replay = get(
        "idempotent-retry",
        "/reports",
        method="POST",
        headers=(f"Idempotency-Key: {key}",),
        form=fields,
    )
    check(replay == created, "Retry did not return the original report")
    rid = created["id"]
    listing = get("list-after", "/reports?include_old=true&limit=100")
    check(listing["total"] == before["total"] + 1, "Retry created an extra report")
    check(
        sum(r["id"] == rid for r in listing["items"]) == 1,
        "Created report missing/duplicated in list",
    )
    body, headers = request(
        "stored-photo", API + created["photo_url"].removeprefix("/api")
    )
    check(
        "content-type: image/jpeg" in headers.lower(), "Photo content type is not JPEG"
    )
    stored = directory / "stored.jpg"
    stored.write_bytes(body)
    with Image.open(stored) as photo:
        check(
            photo.format == "JPEG" and photo.size == (1280, 960), "Invalid stored JPEG"
        )
        check(
            not photo.getexif() and b"Exif\x00\x00" not in body,
            "Stored photo retained EXIF/GPS",
        )
    print("PASS stored JPEG: EXIF and GPS removed", flush=True)

    nearby = get(
        "nearby",
        f"/reports/nearby?lat={latitude}&lon={longitude}&category=pothole&radius_m=150",
    )
    check(
        any(r["id"] == rid and r["distance_m"] < 1 for r in nearby["items"]),
        "Nearby missing report",
    )
    neighbors = get("report-nearby", f"/reports/{rid}/nearby")
    check(all(r["id"] != rid for r in neighbors["items"]), "Nearby includes itself")
    clusters = get("clusters", "/reports/clusters?bbox=-90.6,14.5,-90.4,14.7&zoom=17")
    check(
        any(rid in c["ids"] for c in clusters["clusters"]),
        "Map clusters missing report",
    )
    check(
        sum(c["count"] for c in clusters["clusters"]) == clusters["total"],
        "Cluster count mismatch",
    )
    stats = get("stats", "/stats?include_old=true")
    check(stats["total"] == listing["total"], "Stats/list total mismatch")
    check(
        stats["recibidos"] == stats["total"] - stats["by_status"]["pending"],
        "Received count must exclude reports awaiting verification",
    )
    body, _ = request("csv", API + "/reports.csv?include_old=true&delimiter=semicolon")
    check(body.startswith(b"\xef\xbb\xbf"), "CSV missing UTF-8 BOM")
    rows = list(csv.DictReader(StringIO(body.decode("utf-8-sig")), delimiter=";"))
    check(
        len(rows) == listing["total"] and any(r["id"] == rid for r in rows),
        "CSV/list mismatch",
    )
    print("PASS CSV: BOM and report rows", flush=True)

    path = f"/reports/{rid}/transition"
    get(
        "staff-unauthenticated",
        path,
        expected=401,
        method="POST",
        data={"to": "en_revision"},
    )
    auth = (f"X-Staff-Token: {token}",)
    get(
        "staff-illegal",
        path,
        expected=409,
        method="POST",
        headers=auth,
        data={"to": "resuelto"},
    )
    unchanged = get("detail-after-rejections", f"/reports/{rid}")
    check(unchanged == created, "Failed transitions changed the report/events")
    note = "Prueba local: revisión iniciada."
    updated = get(
        "staff-legal",
        path,
        method="POST",
        headers=auth,
        data={"to": "en_revision", "public_note": note},
    )
    check(updated["state"] == "en_revision", "Staff transition did not persist")
    detail = get("detail-timeline", f"/reports/{rid}")
    event = detail["events"][-1]
    check(
        len(detail["events"]) == len(created["events"]) + 1,
        "Timeline event count mismatch",
    )
    check(
        event["from_state"] == "nuevo"
        and event["to_state"] == "en_revision"
        and event["actor_role"] == "operator"
        and event["public_note"] == note,
        "Staff event missing from public detail",
    )
    check(
        get("list-final", "/reports?include_old=true&limit=100")["total"]
        == before["total"] + 1,
        "Unexpected report count after transitions",
    )
    print(f"PASS local smoke: {calls} real curl requests; report {rid}", flush=True)


def main():
    local = ROOT / ".local"
    local.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="smoke-", dir=local) as directory:
        run(Path(directory))


if __name__ == "__main__":
    main()
