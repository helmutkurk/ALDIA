# Verifier category check with embedding models (2026-11-23)

Proposed by Lorenz (backend, verifier) for the team meeting. Status: **built, measured on a small public
photo set, not yet approved for citizen photos** (privacy, see below).

## Problem

The verifier checked image, place, freshness, sharpness, exposure, EXIF and screen hints, but not whether the
photo shows the reported problem: the `category` check was a stub that always passed. Training our own model
needs a labeled dataset with consent that we do not have yet.

## Decision

Zero-shot classification with a multimodal embedding model, behind the existing `Classifier` interface:

- The photo and two to three short texts per category (Spanish plus one English line) are embedded into the
  same vector space. A "no problem" label (`ninguno`) competes with the six categories: intact streets,
  rooms, screenshots, people, closed manhole covers.
- Each label scores its best cosine similarity. The check passes when the reported category ranks first
  (`EMBEDDING_TOP_K=1`) and reaches `EMBEDDING_MIN_SIMILARITY`.
- Two providers are built and switchable with `EMBEDDING_PROVIDER`; nothing else changes for the API or app:
  - **Google** Gemini Embedding 2 through the Gemini API (plain API key). Google Cloud Vision itself has no
    embeddings, and Vertex AI needs OAuth; the older `multimodalembedding@001` only reads 32 English tokens.
  - **Amazon** Nova 2 Multimodal Embeddings through Bedrock with an API key.
- Heuristic mode with the stub stays the default; model mode is opt-in.

Inspiration: SeeClickFix and FixMyStreet verify reports by people (moderation, staff triage), not by image
analysis; their backends are closed (SeeClickFix) or AGPL-based (FixMyStreet), so only flows were taken.

## Measurements (Google, 2026-11-23)

Set: 32 freely licensed Wikimedia Commons photos (`.local/test-photos/`, git-ignored, licenses in its
`manifest.json`): 4 per category, 4 rooms without a problem and 4 closed manhole covers as hard negatives for
`open_drain`. Script: `backend/verifier/training/compare_embeddings.py`.

| Rule | Real problems accepted | Wrong categories accepted | No-problem photos accepted |
|---|---|---|---|
| top 2 (first draft) | 24/24 | 20 | 8/8 |
| top 1 | 24/24 | 0 | 4/8 (all closed covers taken as `open_drain`) |
| top 1 + closed-cover text in `ninguno` (current) | 23/24 | 0 | 0/8 |

In the first run every real problem had its category in first place, but closed covers scored 0.37–0.39 for
`open_drain` (real open manholes 0.41–0.44). With a closed-cover text in `ninguno` all covers and rooms are
rejected; one open manhole now loses narrowly to `ninguno` (0.432 against 0.426). A minimum similarity above
0.30 only rejects more real problems on this set, so `EMBEDDING_MIN_SIMILARITY` stays 0.0 for Google.
Caveat: 32 photos is very small, not from Guatemala, and the closed-cover text was tuned on the same set; the
numbers are optimistic until measured on new photos.

Amazon: not measured yet; the new AWS account was still in verification (HTTP 403).

## Open points for the team

1. **Privacy.** In model mode every citizen photo goes to Google or Amazon (US regions). Needs a data-protection
   decision and the app's consent text. The Gemini API free tier may use content to improve Google products:
   production needs the paid tier. The verifier only sends a re-encoded JPEG of at most 512 px without metadata.
2. **Costs.** Google: about 258 tokens per image at 0.45 USD per million tokens (preview price), roughly
   0.0001 USD per photo. Amazon: around 0.14 USD per million tokens, image price not published.
3. **Test set.** 30–50 photos per category from Guatemala, taken by the team with consent, then fix
   `EMBEDDING_MIN_SIMILARITY` per provider and compare Google with Amazon on the same set.
4. **Failure policy.** A rejected category currently fails the whole verification. Alternative: route
   `category_mismatch` to manual review instead of rejecting (as the reference products do with people).
