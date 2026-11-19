# backend

- `api/`: receives reports from the app, stores them and serves them to the portal.
- `verifier/`: checks each photo (place, freshness, duplicates, category). The MVP scope depends on what the verifier
  can recognize in photos.

Open questions for the verifier: approach (AI or classic machine learning), how many photos are needed, costs, and how
SeeClickFix and others do it.
