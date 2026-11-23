"""Evaluate the zero-shot category check of one provider on labeled photos.

Photos live outside the repo in `<root>/<label>/*.jpg`. A folder named after a
category holds real problems of that category; any other folder holds photos
without a problem (`ninguno`, closed covers ...), which must not pass for any
category. Each photo is embedded once; the decision then reuses the verifier's
own rule for every claimed category, so the numbers match the service.

Keys come from the environment (AWS_BEARER_TOKEN_BEDROCK, GEMINI_API_KEY) or
are asked for without echo. Results contain scores only, never keys.

    cd backend/verifier
    uv run python -m training.compare_embeddings ../../.local/test-photos \
        --provider google --out ../../.local/eval-google.json
"""

import argparse
import getpass
import json
import os
import statistics
import sys
from pathlib import Path

from PIL import Image, ImageOps

from app.checks.category_prompts import NO_PROBLEM
from app.checks.embedding_classifier import EmbeddingClassifier
from app.config import Settings
from app.embeddings import build_embedder
from app.schemas import CATEGORIES

KEY_NAMES = {"amazon": "AWS_BEARER_TOKEN_BEDROCK", "google": "GEMINI_API_KEY"}


def settings_for(provider: str, args: argparse.Namespace) -> Settings:
    name = KEY_NAMES[provider]
    key = os.environ.get(name) or getpass.getpass(f"{name} (no se muestra): ")
    values: dict[str, object] = {
        "verifier_mode": "model",
        "embedding_provider": provider,
        name.lower(): key,
        "embedding_dimension": args.dimension,
        "embedding_region": args.region,
        "embedding_top_k": args.top_k,
        "embedding_min_similarity": args.min_similarity,
    }
    return Settings.model_validate(values)


def evaluate(root: Path, classifier: EmbeddingClassifier) -> list[dict[str, object]]:
    rows = []
    for path in sorted(root.glob("*/*.jpg")):
        label = path.parent.name
        with Image.open(path) as opened:
            image = ImageOps.exif_transpose(opened).convert("RGB")
        scores = classifier.scores(image)
        ranking = sorted(scores, key=lambda name: (-scores[name], name))
        accepted = [c for c in CATEGORIES if classifier.decide(scores, c).passed]
        rows.append(
            {
                "photo": str(path.relative_to(root)),
                "label": label if label in CATEGORIES else NO_PROBLEM,
                "folder": label,
                "ranking": ranking[:3],
                "scores": {name: round(value, 4) for name, value in scores.items()},
                "accepted_categories": accepted,
            }
        )
        print(f"{path.relative_to(root)!s:28} top: {', '.join(ranking[:3])}")
    return rows


def summary(rows: list[dict[str, object]]) -> dict[str, object]:
    positives = [r for r in rows if r["label"] != NO_PROBLEM]
    negatives = [r for r in rows if r["label"] == NO_PROBLEM]

    def top1(row: dict[str, object]) -> bool:
        ranking = row["ranking"]
        assert isinstance(ranking, list)
        return ranking[0] == row["label"]

    def own_score(row: dict[str, object]) -> float:
        scores = row["scores"]
        assert isinstance(scores, dict)
        return float(scores[row["label"]])

    def accepted(row: dict[str, object]) -> list[str]:
        value = row["accepted_categories"]
        assert isinstance(value, list)
        return value

    true_scores = [own_score(r) for r in positives]
    return {
        "positives": len(positives),
        "negatives": len(negatives),
        "top1_accuracy": sum(map(top1, positives)) / max(len(positives), 1),
        "true_category_passes": sum(r["label"] in accepted(r) for r in positives)
        / max(len(positives), 1),
        "wrong_category_accepts_per_positive": statistics.fmean(
            [len([c for c in accepted(r) if c != r["label"]]) for r in positives]
        )
        if positives
        else 0.0,
        "negatives_with_any_accept": sum(bool(accepted(r)) for r in negatives)
        / max(len(negatives), 1),
        "true_score_min": min(true_scores, default=None),
        "true_score_median": statistics.median(true_scores) if true_scores else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("root", type=Path)
    parser.add_argument("--provider", choices=sorted(KEY_NAMES), required=True)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--dimension", type=int, default=1024)
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--top-k", type=int, default=1)
    parser.add_argument("--min-similarity", type=float, default=0.0)
    args = parser.parse_args()
    settings = settings_for(args.provider, args)
    embedder = build_embedder(settings)
    classifier = EmbeddingClassifier(
        embedder, top_k=args.top_k, min_similarity=args.min_similarity
    )
    try:
        rows = evaluate(args.root, classifier)
    finally:
        embedder.close()
    result = {
        "provider": args.provider,
        "dimension": args.dimension,
        "top_k": args.top_k,
        "min_similarity": args.min_similarity,
        "summary": summary(rows),
        "photos": rows,
    }
    print(json.dumps(result["summary"], indent=1))
    if args.out:
        args.out.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
