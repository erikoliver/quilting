#!/usr/bin/env python3
"""Create a small sanitized sample backup payload from a full Quilt Log ZIP."""

from __future__ import annotations

import argparse
import json
import random
import shutil
import zipfile
from pathlib import Path


SAMPLE_RECIPIENTS = [
    "Avery",
    "Blair",
    "Casey",
    "Devon",
    "Elliot",
    "Finley",
    "Harper",
    "Jordan",
    "Kai",
    "Logan",
    "Morgan",
    "Parker",
    "Quinn",
    "Reese",
    "Riley",
    "Sage",
    "Taylor",
    "Rowan",
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_zip", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--count", type=int, default=18)
    parser.add_argument("--seed", type=int, default=20260608)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    if args.output_directory.exists():
        shutil.rmtree(args.output_directory)
    args.output_directory.mkdir(parents=True)
    (args.output_directory / "thumbnails").mkdir()

    with zipfile.ZipFile(args.source_zip) as backup:
        manifest = json.loads(backup.read("manifest.json"))
        quilts = manifest["quilts"]
        non_done = [quilt for quilt in quilts if quilt["status"] != "1 - Done"]
        done = [quilt for quilt in quilts if quilt["status"] == "1 - Done"]
        selected = non_done + rng.sample(done, max(args.count - len(non_done), 0))
        selected = sorted(selected[: args.count], key=lambda quilt: quilt["sequenceNumber"])

        for index, quilt in enumerate(selected, start=1):
            quilt["sequenceNumber"] = index
            quilt["legacyID"] = index
            quilt["recipient"] = rng.choice(SAMPLE_RECIPIENTS) if quilt["giftedAlready"] else ""
            quilt["notes"] = "Sample data generated for simulator testing."

            for photo_index, photo in enumerate(quilt["photos"], start=1):
                photo["legacyID"] = index * 100 + photo_index
                photo["caption"] = ""
                photo["imageFilename"] = None
                thumbnail = photo["thumbnailFilename"]
                if thumbnail:
                    backup.extract(thumbnail, args.output_directory)

        manifest["exportedAt"] = "2026-06-08T00:00:00Z"
        manifest["syncBehavior"] = (
            "Sanitized sample payload for local simulator testing; thumbnails only, "
            "with randomized recipients and generic notes."
        )
        manifest["quilts"] = selected

    (args.output_directory / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
