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
`GET /health` returns `{"status":"ok","mode":"heuristic"}`.
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
| `VERIFIER_MODE` | `heuristic` | `heuristic`, legacy alias `stub`, or `model` (embedding category check, see below). |
| `MAX_AGE_SECONDS` | `600` | Largest submitted/EXIF age, inclusive; timestamps up to 60 seconds ahead are accepted. |
| `SHARPNESS_MIN` | `80` | Minimum signed Laplacian variance on the 320-pixel grayscale thumbnail. |
| `EXPOSURE_MIN_MEAN` | `12` | Minimum mean grayscale luminance. |
| `EXPOSURE_MAX_MEAN` | `243` | Maximum mean grayscale luminance. |
| `EXPOSURE_MAX_CLIPPED_RATIO` | `0.95` | Maximum fraction of pixels <= 5 or >= 250. |
| `SCREEN_MIN_CORRELATION` | `0.85` | Minimum local periodic correlation peak for a soft screen-photo hint. |

Settings come from the process environment. No environment files are loaded.
`.env.example` lists names only; do not load its empty values as configuration.

## Checks and limitations

- `image`: decode JPEG/PNG by content, reject unsafe decompression/truncation,
  apply EXIF orientation, and require width >= 640 and height >= 480.
- `place`: a coordinate must fall inside one of the inclusive bounding boxes in
  `app/checks/place.py`. Values are `(west, south, east, north)`: GT
  `(-92.3, 13.7, -88.2, 17.9)`, CO `(-81.8, -4.3, -66.8, 13.6)`, MX
  `(-118.5, 14.5, -86.7, 32.8)`. These are broad MVP envelopes, not geographic
  country boundaries; they include some offshore/neighboring areas and do not
  establish that a photo was taken at the submitted coordinate.
- `freshness`: capture time is between 60 seconds in the future and
  `MAX_AGE_SECONDS` in the past, inclusive. This checks submitted metadata,
  not trusted camera attestation.
- `sharpness` and `exposure`: assess usability on an aspect-preserving grayscale
  thumbnail with a maximum side of 320 pixels.
- `exif_time`: checks DateTimeOriginal age and agreement within 120 seconds of
  submitted time. Honors OffsetTimeOriginal; absent offset explicitly assumes UTC.
- `exif_gps`: valid DMS coordinates must be within 150 m of the submitted point.
  Missing time/GPS passes with `exif_missing` and detail `sin EXIF`; malformed
  present metadata fails. EXIF is neither trusted attestation nor proof of place.
- `screen_photo`: periodic-pattern hint on an independent 128-pixel grayscale
  thumbnail. Always passes; a suspected screen produces `possible_screen`.
- `category`: in heuristic mode `StubClassifier` accepts supported categories and
  always returns `detail: "no clasificado (sin modelo)"`, `code: "category_stub"`;
  a stub result is never evidence that a model recognized a street problem. In
  model mode see "Model mode" below.

`app/phash.py` computes a deterministic 64-bit difference hash: grayscale,
9x8 LANCZOS resize, compare each pixel with its right neighbor (`left > right`),
row-major bits, most significant bit first, exactly 16 lowercase hex digits.
The API handles duplicate comparison and appends its own check.
`app/checks/registry.py` orchestrates the checks using `CheckContext`. The image
is decoded/oriented once, and EXIF is normalized into frozen models with explicit
missing/invalid states in `app/metadata.py`. The 320-pixel, 128-pixel and hash
resizes are independent; thumbnails are never resized from each other.
All results retain stable names, codes and order.
Images are processed in memory and never persisted by this service. Application
logs contain no coordinates, filenames or image contents. Supplied commands
disable access logs; configure deployment proxies with the same privacy policy.

## Model mode: embedding category check

`VERIFIER_MODE=model` replaces the stub with `EmbeddingClassifier`
(`app/checks/embedding_classifier.py`): the photo and short texts per category
(`app/checks/category_prompts.py`, Spanish plus one English line, and a
"no problem" label with rooms, screenshots, intact streets and closed covers)
are embedded in one vector space; each label scores its best cosine similarity.
The check passes when the reported category is among the best `EMBEDDING_TOP_K`
labels and reaches `EMBEDDING_MIN_SIMILARITY`.

Providers (`app/embeddings/`, plain `httpx`, no SDK):

| `EMBEDDING_PROVIDER` | Model | Key variable |
| --- | --- | --- |
| `google` | `gemini-embedding-2` via the Gemini API (`x-goog-api-key`) | `GEMINI_API_KEY` |
| `amazon` | `amazon.nova-2-multimodal-embeddings-v1:0` via Bedrock InvokeModel (Bearer API key) | `AWS_BEARER_TOKEN_BEDROCK` |

Startup fails without provider or key, and when the category texts cannot be
embedded. During `/verify`, a provider failure answers `503 classifier_unavailable`;
the API then keeps the report pending. The provider receives a re-encoded JPEG
of at most 512 px without metadata, never coordinates or notes. Keys are
`SecretStr` and never logged. Check keys with `bash training/check_keys.sh`
(asks without echo); measure a provider with `training/compare_embeddings.py`.

```sh
read -rsp "Gemini-Key: " GEMINI_API_KEY; echo; export GEMINI_API_KEY
VERIFIER_MODE=model EMBEDDING_PROVIDER=google uv run uvicorn app.main:create_app \
  --factory --host 127.0.0.1 --port 8001 --no-access-log
```

Privacy: in model mode every citizen photo leaves the server for Google or
Amazon (US regions). That needs the team's data-protection decision and the
app's consent text before real use; the Gemini API free tier may use content
to improve Google products, so production needs a paid tier.

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
hash direction, image size, and model mode with fake provider responses
(`tests/test_embeddings.py`; no test calls a real provider).
