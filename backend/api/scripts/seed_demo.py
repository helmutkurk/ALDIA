"""Seed SYNTHETIC demo reports for Aldia (Guatemala City).

Writes through the SQLAlchemy models (same tables and photo storage as the API),
so the portal and the app see normal reports. Every seeded row has a note that
starts with "[demo]" and a deterministic id, so the script is idempotent and the
rows can be removed again.

Usage (from backend/api, with DATABASE_URL and PHOTO_DIR set, schema migrated):

    uv run python scripts/seed_demo.py            # create what is missing
    uv run python scripts/seed_demo.py --reset    # delete demo rows, then seed again
    uv run python scripts/seed_demo.py --purge    # delete demo rows only

The script refuses to run when ALDIA_ENV, APP_ENV or ENVIRONMENT is "production"
(or "prod"). Photos are generated shapes with a label: no real people or places.
"""

from __future__ import annotations

import argparse
import os
import random
import secrets
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from io import BytesIO
from pathlib import Path
from uuid import UUID, uuid5
from zoneinfo import ZoneInfo

# Allow `python scripts/seed_demo.py` from backend/api (and from /service in the image).
for _candidate in (Path(__file__).resolve().parent.parent, Path.cwd()):
    if (_candidate / "app").is_dir() and str(_candidate) not in sys.path:
        sys.path.insert(0, str(_candidate))

from PIL import Image, ImageDraw, ImageFont  # noqa: E402
from sqlalchemy import delete, select, update  # noqa: E402
from sqlalchemy.exc import OperationalError, ProgrammingError  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402

from app.categories import CATEGORIES  # noqa: E402
from app.config import Settings  # noqa: E402
from app.db import Database  # noqa: E402
from app.models import AuthEvent, IdempotencyRecord, Report, ReportEvent, StaffUser  # noqa: E402
from app.security import hash_password  # noqa: E402
from app.services.storage import PhotoStorage  # noqa: E402
from app.state_machine import STATE_GROUPS, resolution_for  # noqa: E402

PREFIX = "[demo]"
NAMESPACE = UUID("6f1d3c2e-5a4b-4c7d-9e8f-0a1b2c3d4e5f")
PRODUCTION_FLAGS = ("ALDIA_ENV", "APP_ENV", "ENVIRONMENT", "ENV")
PRODUCTION_VALUES = {"production", "prod"}

# Synthetic case locations around a compact Zona 4 neighborhood. These points
# are illustrative anchors, never addresses or observations about actual premises.
ZONES = {"Barrio de demostración, Zona 4": (14.6230, -90.5160)}
BEFORE_AFTER = {24, 25, 26}

NOTES = {
    "accessibility": [
        "Rampa bloqueada por un poste junto al cruce.",
        "Bordillo alto sin rampa frente a la parada.",
        "Rampa rota, una silla de ruedas no puede subir.",
    ],
    "sidewalk": [
        "Acera levantada por raíces, riesgo de caída.",
        "Losetas sueltas en la acera principal.",
        "Acera hundida con escalón de 15 cm.",
    ],
    "pothole": [
        "Bache profundo en el carril derecho.",
        "Hundimiento con agua acumulada tras la lluvia.",
        "Bache grande cerca de la esquina.",
    ],
    "graffiti": [
        "Grafiti sobre el muro de la escuela.",
        "Pintura en la señal de tránsito.",
        "Grafiti en la pared de una parada.",
    ],
    "open_drain": [
        "Alcantarilla sin tapa junto a la banqueta.",
        "Tapa de drenaje rota, hueco visible.",
        "Rejilla ausente, peligro para peatones.",
    ],
    "street_light": [
        "Luminaria apagada desde hace una semana.",
        "Poste con la lámpara colgando.",
        "Tramo de tres luminarias sin luz.",
    ],
}
PUBLIC_NOTES = {
    "en_revision": "Recibimos su reporte y lo estamos revisando.",
    "programado": "Cuadrilla programada para el jueves.",
    "en_proceso": "La cuadrilla ya está trabajando en el lugar.",
    "resuelto": "Reparación terminada, gracias por avisar.",
    "no_procede": "No pudimos confirmar el problema en el lugar.",
    "fuera_de_competencia": "Corresponde a otra institución; se trasladó el aviso.",
}
COLORS = {
    "accessibility": (52, 120, 190),
    "sidewalk": (150, 150, 140),
    "pothole": (90, 80, 75),
    "graffiti": (190, 70, 150),
    "open_drain": (40, 140, 130),
    "street_light": (230, 180, 50),
}
LABELS = dict(CATEGORIES)

# Explicit repair-hour samples for each category; all are synthetic.
EXTRA_REPAIRS = {
    "accessibility": (24, 240, 600),
    "sidewalk": (12, 168, 480),
    "pothole": (6, 48, 288),
    "graffiti": (48, 192, 576),
    "open_drain": (2, 18, 96),
    "street_light": (4, 36, 216),
}
EXTRA_RESOLVED = sum(len(hours) for hours in EXTRA_REPAIRS.values())

# State -> how many reports to create (62 in total, all 11 states).
PLAN: dict[str, int] = {
    "pendiente_verificacion": 2,
    "rechazado_verificador": 3,
    "nuevo": 10,
    "en_revision": 5,
    "programado": 3,
    "en_proceso": 4,
    "resuelto": 8 + EXTRA_RESOLVED,
    "no_procede": 2,
    "fuera_de_competencia": 2,
    "duplicado": 3,
    "oculto": 2,
}
# Chain of states each report passes through after "nuevo".
PATHS: dict[str, list[str]] = {
    "nuevo": [],
    "en_revision": ["en_revision"],
    "programado": ["en_revision", "programado"],
    "en_proceso": ["en_revision", "programado", "en_proceso"],
    "resuelto": ["en_revision", "programado", "en_proceso", "resuelto"],
    "no_procede": ["en_revision", "no_procede"],
    "fuera_de_competencia": ["en_revision", "fuera_de_competencia"],
    "duplicado": ["en_revision", "duplicado"],
}
ASSIGNEES = ["Cuadrilla de movilidad Zona 4", "Cuadrilla de servicios Zona 4"]


@dataclass
class Spec:
    index: int
    state: str
    category: str
    zone: str
    lat: float
    lon: float
    created_at: datetime
    seed: int
    master: int | None = None  # index of the report this one duplicates
    rejection: str | None = None  # "freshness" | "image" | "duplicate"
    repair_hours: float | None = None


class ProductionRefused(RuntimeError):
    pass


def refuse_production(environ: dict[str, str] | None = None) -> None:
    env = os.environ if environ is None else environ
    for name in PRODUCTION_FLAGS:
        if env.get(name, "").strip().lower() in PRODUCTION_VALUES:
            raise ProductionRefused(
                f"Refusing to seed demo data: {name}={env[name]!r} marks production."
            )


def report_id(index: int) -> UUID:
    return uuid5(NAMESPACE, f"aldia-demo-report-{index}")


def build_specs(now: datetime) -> list[Spec]:
    rng = random.Random(20261119)
    zones = list(ZONES)
    categories = [category for category, _label in CATEGORIES]
    specs: list[Spec] = []

    def jitter(zone: str) -> tuple[float, float]:
        lat, lon = ZONES[zone]
        return (
            round(lat + rng.uniform(-0.002, 0.002), 6),
            round(lon + rng.uniform(-0.002, 0.002), 6),
        )

    def add(state: str, **extra: object) -> Spec:
        index = len(specs)
        zone = zones[index % len(zones)] if rng.random() < 0.5 else rng.choice(zones)
        lat, lon = jitter(zone)
        spec = Spec(
            index=index,
            state=state,
            category=categories[index % len(categories)],
            zone=zone,
            lat=lat,
            lon=lon,
            created_at=now,
            seed=rng.randrange(1, 10**6),
        )
        for key, value in extra.items():
            setattr(spec, key, value)
        specs.append(spec)
        return spec

    for state, count in PLAN.items():
        if state in {"duplicado", "rechazado_verificador"}:
            continue
        if state == "resuelto":
            count -= EXTRA_RESOLVED  # preserve the original 44 report ids/states
        for _ in range(count):
            add(state)
    # Staff-marked duplicates share category, place and photo with an open master.
    masters = [s for s in specs if s.state in {"nuevo", "en_revision"}]
    for position in range(PLAN["duplicado"]):
        master = masters[position * 2]
        spec = add("duplicado", master=master.index)
        spec.category = master.category
        spec.zone = master.zone
        spec.lat = round(master.lat + rng.uniform(-0.0001, 0.0001), 6)
        spec.lon = round(master.lon + rng.uniform(-0.0001, 0.0001), 6)
        spec.seed = master.seed
    # Verifier rejections: stale photo, unusable image, and an automatic duplicate.
    for reason in ("freshness", "image", "duplicate"):
        spec = add("rechazado_verificador", rejection=reason)
        if reason == "duplicate":
            master = masters[1]
            spec.master = master.index
            spec.category = master.category
            spec.zone = master.zone
            spec.lat = round(master.lat + 0.0001, 6)
            spec.lon = round(master.lon - 0.0001, 6)
            spec.seed = master.seed
    # Append rather than insert: an existing demo gains new rows on its next seed.
    for category, hours in EXTRA_REPAIRS.items():
        for repair_hours in hours:
            spec = add("resuelto", repair_hours=repair_hours)
            spec.category = category
    # A reproducible 60-day story: the initial backlog is followed by eight
    # weekly repairs, then a concentrated neighborhood inspection 29 days ago.
    # Keep the category-duration samples inside the default 30-day dashboard.
    unresolved = [s for s in specs if s.state != "resuelto"]
    for position, spec in enumerate(unresolved):
        spec.created_at = now - timedelta(
            days=60 - 55 * position / (len(unresolved) - 1)
        )
    originals = [s for s in specs if s.state == "resuelto" and s.repair_hours is None]
    for position, spec in enumerate(originals):
        spec.created_at = now - timedelta(days=59.8)
        # Finished at ages 53, 46, ..., 4 days; exact duration drives events.
        spec.repair_hours = (59.8 - (53 - 7 * position)) * 24
    for spec in specs:
        if spec.state == "resuelto" and spec not in originals:
            spec.created_at = now - timedelta(days=29)
    # Duplicates and the automatic duplicate rejection come after their master:
    # masters are at least two days old, duplicates are created 6 hours later.
    by_index = {s.index: s for s in specs}
    for spec in specs:
        if spec.master is not None:
            master = by_index[spec.master]
            master.created_at = min(
                master.created_at, now - timedelta(days=2, hours=rng.randint(0, 20))
            )
    for spec in specs:
        if spec.master is not None:
            spec.created_at = by_index[spec.master].created_at + timedelta(
                hours=6, minutes=rng.randint(0, 90)
            )
    return specs


def make_photo(spec: Spec) -> bytes:
    """800x600 synthetic JPEG: coloured shapes plus a label; no real scenes."""
    if spec.index in BEFORE_AFTER:
        return make_before_after(spec)
    rng = random.Random(spec.seed)
    base = COLORS[spec.category]
    image = Image.new("RGB", (800, 600), tuple(min(255, c + 60) for c in base))
    draw = ImageDraw.Draw(image)
    for row in range(0, 600, 12):  # vertical gradient helps the difference hash
        shade = int(40 * row / 600)
        draw.rectangle(
            [0, row, 800, row + 12], fill=tuple(max(0, c - shade) for c in base)
        )
    for _ in range(rng.randint(5, 8)):
        x, y = rng.randint(0, 700), rng.randint(60, 500)
        w, h = rng.randint(60, 260), rng.randint(40, 200)
        color = tuple(rng.randint(20, 235) for _ in range(3))
        box = [x, y, min(800, x + w), min(560, y + h)]
        if rng.random() < 0.5:
            draw.ellipse(box, fill=color)
        else:
            draw.rectangle(box, fill=color)
    try:
        font = ImageFont.load_default(size=34)
    except TypeError:  # older Pillow without scalable default font
        font = ImageFont.load_default()
    draw.rectangle([0, 0, 800, 56], fill=(20, 20, 20))
    draw.text(
        (16, 10),
        f"DEMO SINTETICO - {spec.category} #{spec.index}",
        fill="white",
        font=font,
    )
    draw.rectangle([0, 560, 800, 600], fill=(20, 20, 20))
    draw.text(
        (16, 564),
        f"{spec.zone} - foto generada, no real",
        fill=(220, 220, 220),
        font=font,
    )
    if spec.rejection == "image":
        image = image.resize((400, 300), Image.Resampling.LANCZOS)
    out = BytesIO()
    image.save(out, format="JPEG", quality=88)
    return out.getvalue()


def make_before_after(spec: Spec) -> bytes:
    """Two distinct synthetic scenes in the existing single-photo contract."""
    image = Image.new("RGB", (800, 600), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=28)
    small = ImageFont.load_default(size=19)
    for x, repaired in ((0, False), (400, True)):
        draw.rectangle((x, 60, x + 398, 550), fill=(180, 188, 190))
        draw.rectangle((x, 330, x + 398, 550), fill=(76, 82, 85))
        draw.rectangle((x, 285, x + 398, 328), fill=(217, 210, 193))
        for offset in (20, 140, 260):
            draw.rectangle((x + offset, 455, x + offset + 75, 465), fill="white")
        if spec.category == "pothole":
            if repaired:
                draw.rectangle((x + 90, 370, x + 300, 430), fill=(62, 66, 69))
                draw.text((x + 90, 490), "Bache reparado", font=small, fill="white")
            else:
                draw.ellipse((x + 90, 355, x + 300, 440), fill=(35, 28, 23))
                draw.ellipse((x + 130, 380, x + 260, 425), fill=(92, 117, 122))
        elif spec.category == "sidewalk":
            for y in (150, 215, 280):
                draw.line((x + 25, y, x + 375, y), fill=(115, 120, 122), width=4)
            if repaired:
                draw.rectangle((x + 110, 170, x + 290, 260), fill=(196, 200, 200))
                draw.text((x + 80, 490), "Acera nivelada", font=small, fill="white")
            else:
                draw.line(
                    [(x + 110, 170), (x + 200, 220), (x + 140, 270)],
                    fill=(60, 55, 52),
                    width=14,
                )
                draw.polygon(
                    [(x + 210, 185), (x + 300, 165), (x + 315, 230), (x + 220, 250)],
                    fill=(136, 126, 114),
                )
        else:
            if repaired:
                draw.polygon(
                    [(x + 120, 240), (x + 280, 240), (x + 310, 370), (x + 90, 370)],
                    fill=(225, 214, 180),
                )
                for y in range(280, 360, 15):
                    draw.line((x + 125, y, x + 275, y), fill=(155, 145, 115), width=3)
                draw.text((x + 70, 490), "Rampa accesible", font=small, fill="white")
            else:
                draw.rectangle((x + 85, 285, x + 315, 340), fill=(123, 114, 102))
                draw.text((x + 65, 490), "Bordillo sin rampa", font=small, fill="white")
        draw.rectangle((x, 60, x + 398, 110), fill=(25, 27, 30))
        draw.text(
            (x + 20, 70), "DESPUES" if repaired else "ANTES", font=font, fill="white"
        )
    draw.text(
        (16, 14),
        f"[demo] Caso #{spec.index} · {LABELS[spec.category]}",
        font=font,
        fill=(25, 27, 30),
    )
    draw.text(
        (16, 564),
        "Imagenes sinteticas · Zona 4 · No es evidencia de obras reales",
        font=small,
        fill=(25, 27, 30),
    )
    output = BytesIO()
    image.save(output, format="JPEG", quality=90)
    return output.getvalue()


def dhash(data: bytes) -> str:
    """Same 64-bit difference hash as backend/verifier/app/phash.py."""
    with Image.open(BytesIO(data)) as image:
        pixels = image.convert("L").resize((9, 8), Image.Resampling.LANCZOS).tobytes()
    value = 0
    for row in range(8):
        for column in range(8):
            index = row * 9 + column
            value = (value << 1) | int(pixels[index] > pixels[index + 1])
    return f"{value:016x}"


def verification_for(spec: Spec) -> dict[str, object]:
    def check(name: str, passed: bool, detail: str) -> dict[str, object]:
        return {"name": name, "passed": passed, "detail": detail}

    rejection = spec.rejection
    checks = [
        check(
            "image",
            rejection != "image",
            "[demo] Foto de baja resolución; vuelve a tomarla."
            if rejection == "image"
            else "[demo] Imagen legible de 800 × 600.",
        ),
        check("place", True, "[demo] Ubicación dentro de Guatemala."),
        check(
            "freshness",
            rejection != "freshness",
            "[demo] Foto tomada hace 30 minutos; se requiere una captura reciente."
            if rejection == "freshness"
            else "[demo] Captura reciente al enviar el reporte.",
        ),
        check(
            "category", True, "[demo] No clasificado: decisión ilustrativa, sin modelo."
        ),
        check(
            "duplicate",
            rejection != "duplicate",
            "[demo] Ya existe una foto similar de esta categoría a menos de 50 m."
            if rejection == "duplicate"
            else "[demo] Sin coincidencias cercanas en este caso.",
        ),
    ]
    return {"passed": rejection is None, "mode": "stub", "checks": checks}


def note_for(spec: Spec) -> str:
    featured = {
        24: "Cruce A: bordillo sin rampa; se construyó un acceso peatonal.",
        25: "Pasaje B: acera rota; se sustituyeron y nivelaron las losetas.",
        26: "Calle C: bache con agua; se reparó la superficie del carril.",
    }
    text = featured.get(spec.index, NOTES[spec.category][spec.index % 3])
    return f"{PREFIX} {text} ({spec.zone})"


def build_rows(
    spec: Spec, by_index: dict[int, Spec], now: datetime
) -> tuple[Report, list[ReportEvent], bytes]:
    rng = random.Random(spec.seed + spec.index)
    rid = report_id(spec.index)
    photo = make_photo(spec)
    created = spec.created_at
    state = spec.state
    pending = state == "pendiente_verificacion"
    answered = None if pending else created + timedelta(seconds=rng.randint(2, 9))
    events = [
        ReportEvent(
            report_id=rid,
            actor_role="system",
            from_state=None,
            to_state="pendiente_verificacion",
            at=created,
        )
    ]
    last_at = created
    current = "pendiente_verificacion"
    report = Report(
        id=rid,
        category=spec.category,
        latitude=spec.lat,
        longitude=spec.lon,
        captured_at=created - timedelta(seconds=rng.randint(3, 20)),
        created_at=created,
        note=note_for(spec),
        phash=None if pending else dhash(photo),
        status="pending" if pending else ("rejected" if spec.rejection else "verified"),
        verification=None if pending else verification_for(spec),
        verified_at=answered,
    )
    if spec.rejection == "freshness":
        report.captured_at = created - timedelta(seconds=1800)
    if answered is not None:
        first = "rechazado_verificador" if spec.rejection else "nuevo"
        events.append(
            ReportEvent(
                report_id=rid,
                actor_role="system",
                from_state=current,
                to_state=first,
                at=answered,
            )
        )
        current, last_at = first, answered
    path = PATHS.get(state, [])
    if state == "oculto":
        # Hidden by a supervisor after a few days, from "nuevo".
        path = []
    span = max((now - last_at).total_seconds() - 3600, 3600)
    step = span / (len(path) + 2)
    assignee = rng.choice(ASSIGNEES) if path else None
    for position, target in enumerate(path, start=1):
        at = (
            answered + timedelta(hours=spec.repair_hours * position / len(path))
            if spec.repair_hours is not None and answered is not None
            else last_at + timedelta(seconds=step * (0.6 + 0.4 * rng.random()))
        )
        public = PUBLIC_NOTES.get(target)
        internal = None
        if target == "duplicado":
            public = "Ya existe un reporte igual; se unifica el seguimiento."
        if target in {"programado", "en_proceso"} and rng.random() < 0.5:
            internal = "[demo] Material en bodega, asignar camión."
        if public:
            public = f"{PREFIX} {public}"
        events.append(
            ReportEvent(
                report_id=rid,
                actor_role="supervisor"
                if target == "resuelto" and rng.random() < 0.3
                else "operator",
                from_state=current,
                to_state=target,
                public_note=public,
                internal_note=internal,
                at=at,
            )
        )
        if public:
            report.public_note = public
        current, last_at = target, at
    if state == "oculto":
        at = last_at + (now - last_at) / 2
        events.append(
            ReportEvent(
                report_id=rid,
                actor_role="supervisor",
                from_state=current,
                to_state="oculto",
                internal_note="Contenido no apropiado en la foto (demo).",
                at=at,
            )
        )
        report.previous_state = current
        current, last_at = "oculto", at
    report.state = current
    report.resolution = resolution_for(current)
    report.state_changed_at = last_at
    report.assignee = assignee
    if assignee:
        report.assigned_at = events[2].at if len(events) > 2 else last_at
    if current == "resuelto":
        report.resolved_at = last_at
    if current in {"no_procede", "fuera_de_competencia", "duplicado"}:
        report.closed_at = last_at
    if current == "rechazado_verificador":
        report.closed_at = last_at
    if spec.master is not None and current == "duplicado":
        report.duplicate_of = report_id(by_index[spec.master].index)
    assert STATE_GROUPS[report.state]  # sanity: known state
    return report, events, photo


def demo_ids(session: Session) -> list[UUID]:
    return list(
        session.scalars(select(Report.id).where(Report.note.like(f"{PREFIX}%")))
    )


def purge(session: Session, storage: PhotoStorage) -> int:
    ids = demo_ids(session)
    if not ids:
        return 0
    session.execute(update(Report).where(Report.id.in_(ids)).values(duplicate_of=None))
    session.execute(
        delete(IdempotencyRecord).where(IdempotencyRecord.report_id.in_(ids))
    )
    session.execute(delete(ReportEvent).where(ReportEvent.report_id.in_(ids)))
    session.execute(delete(Report).where(Report.id.in_(ids)))
    session.commit()
    for rid in ids:
        storage.delete(rid)
    return len(ids)


def seed(
    session: Session, storage: PhotoStorage, now: datetime | None = None
) -> dict[str, int]:
    """Create missing demo reports; return counters. Safe to run repeatedly."""
    now = now or datetime.now(UTC)
    specs = build_specs(now)
    by_index = {s.index: s for s in specs}
    existing = set(
        session.scalars(
            select(Report.id).where(Report.id.in_([report_id(s.index) for s in specs]))
        )
    )
    created = skipped = 0
    # Masters first so duplicate_of never points at a missing row.
    for spec in sorted(specs, key=lambda s: (s.master is not None, s.index)):
        rid = report_id(spec.index)
        if rid in existing:
            skipped += 1
            if not storage.path(rid).exists():
                storage.save(rid, make_photo(spec))
            continue
        report, events, photo = build_rows(spec, by_index, now)
        for event in events:
            event.actor = {"operator": "operador", "supervisor": "supervisor"}.get(
                event.actor_role, "system"
            )
        session.add(report)
        session.flush()
        session.add_all(events)
        storage.save(rid, photo)
        created += 1
    session.commit()
    return {"created": created, "skipped": skipped}


def seed_users(session: Session, settings: Settings) -> None:
    """Print a random initial password once, only on explicit local development."""
    if settings.env != "dev":
        return
    for username, role in (("operador", "operator"), ("supervisor", "supervisor")):
        if session.scalar(select(StaffUser.id).where(StaffUser.username == username)):
            continue
        password = secrets.token_urlsafe(24)
        session.add(
            StaffUser(
                username=username, role=role, password_hash=hash_password(password)
            )
        )
        session.add(
            AuthEvent(
                actor="system",
                actor_role="system",
                action="demo_user_created",
                target=username,
            )
        )
        session.commit()
        print(f"Development account {username}; initial password: {password}")


def summarize(session: Session) -> str:
    rows = list(session.scalars(select(Report).where(Report.note.like(f"{PREFIX}%"))))
    states = Counter(r.state for r in rows)
    categories = Counter(r.category for r in rows)
    lines = [f"Demo reports in database: {len(rows)}", "By state:"]
    lines += [f"  {state:<24} {states.get(state, 0)}" for state in PLAN]
    lines.append("By category:")
    lines += [f"  {cid:<24} {categories.get(cid, 0)}" for cid, _ in CATEGORIES]
    if rows:
        oldest = min(r.created_at for r in rows)
        newest = max(r.created_at for r in rows)
        lines.append(f"Created between {oldest:%Y-%m-%d} and {newest:%Y-%m-%d}")
        weekly: dict[str, list[int]] = {}
        for report in rows:
            if report.state == "oculto":
                continue
            for at, column in ((report.created_at, 0), (report.resolved_at, 1)):
                if at is not None and (column == 1 or report.verified_at is not None):
                    aware = at.replace(tzinfo=UTC) if at.tzinfo is None else at
                    week = aware.astimezone(ZoneInfo("America/Guatemala")).strftime(
                        "%G-W%V"
                    )
                    weekly.setdefault(week, [0, 0])[column] += 1
        lines.append(
            "Weekly cumulative answered public reports / resolved / resolved share:"
        )
        received = resolved = 0
        for week, counts in sorted(weekly.items()):
            received += counts[0]
            resolved += counts[1]
            lines.append(
                f"  {week}: {received} / {resolved} / {resolved / received:.1%}"
            )
        lines.append("Before/after synthetic comparison cases:")
        lines += [f"  /#/reports/{report_id(index)}" for index in sorted(BEFORE_AFTER)]
    lines.append(
        "Note: the portal list defaults to the last 30 days; "
        "set include_old=true or a wider date range to see all of them."
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--reset", action="store_true", help="delete demo rows, then seed again"
    )
    group.add_argument("--purge", action="store_true", help="delete demo rows only")
    args = parser.parse_args(argv)
    try:
        refuse_production()
    except ProductionRefused as exc:
        print(exc, file=sys.stderr)
        return 2
    settings = Settings()
    database = Database(settings.database_url)
    storage = PhotoStorage(settings.photo_dir)
    try:
        with database.sessions() as session:
            if args.reset or args.purge:
                print(f"Removed {purge(session, storage)} demo reports.")
            if not args.purge:
                counters = seed(session, storage)
                seed_users(session, settings)
                print(
                    f"Created {counters['created']}, "
                    f"already present {counters['skipped']}."
                )
            print(summarize(session))
    except (OperationalError, ProgrammingError) as exc:
        print(
            "Database error: is the schema migrated (uv run alembic upgrade head)? "
            f"{type(exc).__name__}",
            file=sys.stderr,
        )
        return 1
    finally:
        database.engine.dispose()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
