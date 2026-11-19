# Aldia verifier

Internal Python 3.12 / FastAPI image verifier, port 8001. Keep this service off
the public internet. The binding interface is
[`documentation/api-contract.md`](../../documentation/api-contract.md).

## Install and run

From `backend/verifier`:

```sh
uv sync --frozen
uv run uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8001 --no-access-log
```

`make install` and `make dev` are available; development enables reload.
`GET /health` returns `{"status":"ok","mode":"stub"}`.
`POST /verify` accepts multipart fields `photo`, `category`, `latitude`,
`longitude`, `captured_at`. All other or repeated fields are rejected. Coordinates
must be finite and in range, and the capture time must include a timezone.
Errors use `{"error":{"code":"...","message":"..."}}` with generic messages.
Undecodable or unsupported image content returns 422, since no meaningful hash
can be computed. Decodable images return the contract's checks, including failed
checks. There is a fixed 32 MiB photo safety limit, plus 64 KiB of multipart
headers/fields, enforced before parsing and regardless of Content-Length. This
allows the API to send an image re-encoded from an upload of up to 8 MiB.

| Variable | Default | Meaning |
| --- | --- | --- |
| `VERIFIER_MODE` | `stub` | `stub` or `model`; model mode fails clearly until a trained classifier is integrated. |
| `MAX_AGE_SECONDS` | `600` | Largest allowed age, inclusive; timestamps up to 60 seconds ahead are accepted. |

Settings come from the process environment. No environment files are loaded.
`.env.example` lists names only; do not load its empty values as configuration.

## Checks and limitations

- `image`: decode JPEG/PNG by content, reject unsafe decompression/truncation,
  apply EXIF orientation, and require width >= 640 and height >= 480.
- `place`: a coordinate must fall inside one of the inclusive bounding boxes in
  `app/checks.py`. Values are `(west, south, east, north)`: GT
  `(-92.3, 13.7, -88.2, 17.9)`, CO `(-81.8, -4.3, -66.8, 13.6)`, MX
  `(-118.5, 14.5, -86.7, 32.8)`. These are broad MVP envelopes, not geographic
  country boundaries; they include some offshore/neighboring areas and do not
  establish that a photo was taken at the submitted coordinate.
- `freshness`: capture time is between 60 seconds in the future and
  `MAX_AGE_SECONDS` in the past, inclusive. This checks submitted metadata,
  not trusted camera attestation.
- `category`: `StubClassifier` accepts supported categories and always returns
  `detail: "stub: not classified"`. A stub result is never evidence that a model
  recognized a street problem.

`app/phash.py` computes a deterministic 64-bit difference hash: grayscale,
9x8 LANCZOS resize, compare each pixel with its right neighbor (`left > right`),
row-major bits, most significant bit first, exactly 16 lowercase hex digits.
The API handles duplicate comparison and appends its own check.
Images are processed in memory and never persisted by this service. Application
logs contain no coordinates, filenames or image contents. Supplied commands
disable access logs; configure deployment proxies with the same privacy policy.

## Plug in Lorenz's trained model

`app/checks.py` defines `Classifier.classify(image, category) -> Check`. Inputs
are decoded, oriented RGB Pillow images and stable category IDs. Implement this
Protocol in a new module under `app/`, returning `name="category"`, a Boolean
`passed`, and a concise explanation in `detail`. Do not use the stub's success
value as a model prediction. Set and document any trained confidence thresholds.

In `app/main.py`, replace the explicit `NotImplementedError` branch for
`VERIFIER_MODE=model` with model initialization and assign that instance to the
`Classifier` variable. Load weights once at startup, fail startup if unavailable,
and preserve `mode="model"` in responses and health. Keep `StubClassifier` for
stub mode and add deterministic tests for model preprocessing and decisions.
Any required model runtime dependencies need the team's approval and exact uv
pins. Never silently fall back to the stub when model mode was requested.

Training notebooks, data preparation and training scripts belong in
[`training/`](training/README.md). Runtime prediction code belongs in `app/`.
Keep model weights, datasets and photos outside this public repository; deploy
weights through a private artifact store or mounted volume. The Docker context
excludes `training/`.

## Verify and build

```sh
uv sync
uv run ruff check
uv run ruff format --check
uv run mypy app
uv run pytest

docker build -t aldia-verifier .
docker run --rm --network aldia --name verifier aldia-verifier
```

The Dockerfile uses a frozen, production-only uv environment in a multi-stage
image, runs as UID/GID 10001, and checks `/health`. No public port is published by
the example. `make test`, `make lint`, and `make fmt` provide local shortcuts.
There is no database and no migration step for this service. Tests use synthetic
images and exercise bounding boxes, freshness boundaries, invalid requests,
hash direction, image size and explicit failure of unimplemented model mode.
