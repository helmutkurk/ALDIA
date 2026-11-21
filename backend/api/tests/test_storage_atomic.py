"""Failure semantics shared by full-image and thumbnail atomic writes."""

from pathlib import Path
from uuid import uuid4

import pytest
from test_reports import photo

from app.services.storage import PhotoStorage


@pytest.mark.parametrize("operation", ["photo", "thumbnail"])
@pytest.mark.parametrize("failure", ["fsync", "replace"])
def test_failed_image_write_retains_source_and_cleans_temporary(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    operation: str,
    failure: str,
) -> None:
    storage = PhotoStorage(tmp_path / "photos")
    report_id = uuid4()
    original = photo()
    storage.save(report_id, original)
    source = storage.path(report_id)

    def fail(*args: object) -> None:
        raise OSError("simulated write failure")

    monkeypatch.setattr(f"app.services.storage.os.{failure}", fail)
    with pytest.raises(OSError, match="simulated write failure"):
        if operation == "photo":
            storage.save(report_id, b"replacement bytes")
        else:
            storage.thumbnail(report_id)
    assert source.read_bytes() == original
    assert set(storage.root.iterdir()) == {source}
    assert storage.root.stat().st_mode & 0o777 == 0o700


def test_atomic_photo_replacement_and_thumbnail_reuse(tmp_path: Path) -> None:
    storage = PhotoStorage(tmp_path / "photos")
    report_id = uuid4()
    storage.save(report_id, b"previous bytes")
    replacement = photo()
    storage.save(report_id, replacement)
    target = storage.thumbnail(report_id)
    assert target is not None
    assert storage.path(report_id).read_bytes() == replacement
    thumbnail = target.read_bytes()
    modified = target.stat().st_mtime_ns
    assert storage.thumbnail(report_id) == target
    assert target.read_bytes() == thumbnail
    assert target.stat().st_mtime_ns == modified
    assert set(storage.root.iterdir()) == {storage.path(report_id), target}
