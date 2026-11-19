# Portal API contract (draft v0.1)

What the portal expects from `backend/api`. The portal already works against this contract with
synthetic data (`src/data/mock-source.js`); pointing it at a real backend is a URL change:
`index.html?source=api&api=<base url>` (default base: `/api/v1`, same origin).

Draft for Lorenz (backend) and the app team to review. Field names and statuses can still change;
change this file and `src/domain/schema.js` together.

## Concepts

- **Report**: one photo sent by one citizen (or one "after" photo). The app creates reports.
- **Case**: one problem in one place. Reports of the same category within 20 m are grouped into a
  case (FixMyStreet calls this "nearby problems"). The government works on cases, not on reports.
- **Credibility** comes from independent people whose photo passed the verifier, never from the
  number of photos.
- **Rule**: the government can never mark a case as fixed. Only a verified "after" photo
  (`kind: "repair_check"`) closes it as `fixed`; a failed one turns `fix_claimed` into `reopened`.

## Endpoints

### `GET /cases[?updated_since=<ISO time>]`

Response `200`:

```json
{
  "serverTime": "2026-11-19T18:00:00.000Z",
  "cases": [
    {
      "id": "ALD-GT-04812",
      "category": "pothole",
      "status": "in_review",
      "lat": 14.6405,
      "lng": -90.5135,
      "address": "6a. Avenida y 12 Calle, Zona 1",
      "zone": "Zona 1",
      "nearSensitive": false,
      "reports": [
        {
          "id": "rep_1001",
          "kind": "report",
          "category": "pothole",
          "lat": 14.64051,
          "lng": -90.51352,
          "accuracyM": 8,
          "createdAt": "2026-11-09T15:20:00.000Z",
          "severity": "damages_cars",
          "reporterId": "vec_8f3a2c",
          "verification": { "status": "passed", "confidence": 0.91 },
          "photoUrl": "/api/v1/photos/pho_77"
        }
      ],
      "history": [
        { "status": "new", "at": "2026-11-09T15:20:00.000Z", "by": "sistema" },
        { "status": "in_review", "at": "2026-11-10T09:00:00.000Z", "by": "gobierno", "note": "Asignado a Obras." }
      ]
    }
  ]
}
```

With `updated_since`, the backend may return only cases that changed after that time; the portal
merges them by `id`. Without it, it returns all cases visible to the session.

### `POST /cases/:id/status`

Body: `{ "status": "<next status>", "note": "<optional, max 500 chars>" }`. Response `200`: the
updated case (same shape as above). Errors: `401`/`403` no permission, `404` unknown case, `409`
the case changed meanwhile, `422` transition not allowed.

### `GET /photos/:photoId`

The stored JPEG, already with faces and plates blurred. Photo URLs in reports may be same-origin
paths or `https` URLs.

## Values

| Field | Values |
|---|---|
| `category` | `pothole`, `sidewalk`, `ramp`, `street_light`, `drain_cover`, `signage` |
| `status` | `new`, `in_review`, `scheduled`, `in_progress`, `fix_claimed`, `reopened`, `fixed`, `not_responsible`, `duplicate` |
| `kind` | `report` (problem photo), `confirm` (neighbor confirms), `repair_check` (after photo) |
| `severity` | `minor`, `damages_cars`, `dangerous` |
| `verification.status` | `passed`, `failed`, `pending` (+ optional `confidence` 0-1, `reason` in Spanish) |
| `history[].by` | `gobierno`, `sistema`, `vecino` |
| ids | `[A-Za-z0-9_-]{1,64}` |
| times | ISO 8601 UTC |

Status changes allowed from the portal (`src/domain/statuses.js`):

| From | To |
|---|---|
| `new` | `in_review`, `scheduled`, `in_progress`, `not_responsible`, `duplicate` |
| `in_review` | `scheduled`, `in_progress`, `not_responsible`, `duplicate` |
| `scheduled` | `in_progress`, `not_responsible` |
| `in_progress` | `fix_claimed`, `scheduled` |
| `reopened` | `in_review`, `scheduled`, `in_progress` |
| `not_responsible`, `duplicate` | `in_review` |
| `fix_claimed`, `fixed` | none (only the verifier moves them) |

## Privacy

- `reporterId` is an anonymous, stable id per person (for example a salted hash). Never a name,
  phone number or ID number. The portal never shows or exports it.
- The portal validates every field (`src/domain/schema.js`) and drops invalid reports.

## Exports

The portal exports the visible cases as GeoJSON and as Open311 GeoReport v2 service requests
(`src/domain/exports.js`), without reporter ids.
