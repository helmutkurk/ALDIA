# Verifier training workspace

Lorenz: place training notebooks, dataset preparation and training/evaluation
scripts here. Runtime inference adapters implementing `Classifier` belong in
`../app/`; see the verifier README for integration steps.

This placeholder includes no model, dataset or training claims. Before adding a
training workflow, document the dataset source and consent/license, category ID
mapping from the API contract, train/validation/test split, preprocessing,
metrics, selected thresholds, model version, and the reproducible training command.
Keep photos, personal data, credentials, model checkpoints and weights outside
the public repository. Use synthetic fixtures for committed tests. Reference
private artifact locations without embedding access tokens. Training files are
excluded from runtime Docker builds.
