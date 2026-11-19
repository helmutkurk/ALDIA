# Reference products: FixMyStreet and SeeClickFix

Decision 2026-11-19 (Helmut): the **portal** follows FixMyStreet (mySociety, UK, open source), the **app** follows
SeeClickFix. Aldia is the union of both, in Spanish, adapted to Guatemala, with photo verification as the difference.

## Licensing: we copy ideas, not code

- FixMyStreet (`github.com/mysociety/fixmystreet`, Perl/Catalyst) is published under mySociety's own license (AGPL
  based). Copying its code or templates would oblige this repo to follow that license. We read it to learn flows and
  data model and write our own code.
- SeeClickFix publishes only API documentation and the Open311 reference tools (`dev.seeclickfix.com`,
  `Open311`); its apps and server are closed. We reproduce the user flow from the public product and its API docs.
- Open311 GeoReport v2 is an open standard: implementing it is allowed and gives interoperability with city systems.
- Before any future reuse of code or text from either project, check the license file in that repo and record it in
  `documentation/decisions/`.

## What we take from FixMyStreet (portal)

| FixMyStreet page | Aldia portal |
|---|---|
| Front page: enter a place | Place search, default view Guatemala City |
| "Around": map with pins plus list of nearby reports | Map and list side by side, filters by category and status |
| Report page with photo, status and updates | Report detail with photo, verification checks and status history |
| Reports by council and area | Reports by municipality (field planned, not in v0) |
| Council dashboard with counts and CSV export | Dashboard: counts by category and status, CSV export |
| Open311 server | Read-only Open311 GeoReport v2 export |

## What we take from SeeClickFix (app)

| SeeClickFix flow | Aldia app |
|---|---|
| Feed and map of nearby issues | Home with map and list of nearby reports |
| Report: place a pin, choose category, add photo and description | Four steps: location, category, live photo, note |
| Status shown to the citizen: open, acknowledged, closed | `resolution`: open, acknowledged, fixed (set by the government later) |
| My reports | "Mis reportes" (ids kept on the device) |
| Watch, vote (+1) and comment | Not in the MVP; listed as future work |

## What Aldia adds

- Live camera only (no gallery in release builds) and server-side verification of place, freshness, duplicates and
  category; the citizen sees why a photo failed and can retake it.
- Spanish (Guatemala) text; categories for Guatemala (accessibility, sidewalks, potholes, graffiti, open drains,
  street lights); privacy: EXIF stripped, no personal data in the report.
- Payments and rewards: undecided; first the proof of concept for the government.

## Open points

- Municipality and department fields (needs a boundary dataset for Guatemala).
- Authentication for the government portal and for status changes.
- Open311 write endpoints (government systems posting status changes).
