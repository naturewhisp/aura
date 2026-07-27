from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from urllib.parse import quote

from huggingface_hub import HfApi

COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$", re.IGNORECASE)
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$", re.IGNORECASE)


@dataclass(frozen=True)
class ResolvedArtifact:
    logicalModelId: str
    applicationModelId: str | None
    repository: str
    filename: str
    revision: str
    downloadUrl: str
    sizeBytes: int
    sha256: str
    quantization: str
    role: str
    intendedUsage: str
    license: str | None
    verificationStatus: str


def read_metadata_value(metadata: object, *names: str) -> object | None:
    if metadata is None:
        return None

    if isinstance(metadata, dict):
        for name in names:
            if name in metadata and metadata[name] is not None:
                return metadata[name]
        return None

    for name in names:
        value = getattr(metadata, name, None)
        if value is not None:
            return value

    return None


def resolve_artifact(api: HfApi, artifact_source: dict) -> ResolvedArtifact:
    logical_model_id = artifact_source["logicalModelId"]
    application_model_id = artifact_source.get("applicationModelId")
    repository = artifact_source["repository"]
    filename = artifact_source["filename"]
    requested_revision = artifact_source.get("revision")
    quantization = artifact_source["quantization"]
    role = artifact_source["role"]
    intended_usage = artifact_source["intendedUsage"]

    resolved_revision = requested_revision

    if not resolved_revision or resolved_revision in ("main", "HEAD"):
        head_info = api.model_info(repo_id=repository, files_metadata=True)
        resolved_revision = head_info.sha

    if not resolved_revision:
        raise RuntimeError(f"Missing repository revision for {repository}")

    resolved_revision = resolved_revision.lower().strip()

    if COMMIT_PATTERN.fullmatch(resolved_revision) is None:
        raise RuntimeError(
            f"Revision for {repository} is not a full 40-char commit SHA: {resolved_revision!r}"
        )

    pinned_info = api.model_info(
        repo_id=repository, revision=resolved_revision, files_metadata=True
    )

    if pinned_info.sha is None or pinned_info.sha.lower() != resolved_revision:
        raise RuntimeError(
            f"Unexpected commit for {repository}: requested={resolved_revision}, resolved={pinned_info.sha}"
        )

    matches = [
        sibling
        for sibling in pinned_info.siblings
        if sibling.rfilename == filename
    ]

    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one file {filename!r} in {repository}@{resolved_revision}, found {len(matches)}"
        )

    file_info = matches[0]

    size_bytes = getattr(file_info, "size", None)
    if not isinstance(size_bytes, int) or size_bytes <= 0:
        lfs_size = read_metadata_value(getattr(file_info, "lfs", None), "size")
        if isinstance(lfs_size, int):
            size_bytes = lfs_size

    if not isinstance(size_bytes, int) or size_bytes <= 0:
        raise RuntimeError(
            f"Missing or invalid size for {repository}/{filename}"
        )

    lfs = getattr(file_info, "lfs", None)
    sha256 = read_metadata_value(lfs, "sha256", "oid")

    if not isinstance(sha256, str):
        raise RuntimeError(
            f"Missing SHA-256 metadata for {repository}/{filename}"
        )

    sha256 = sha256.lower().strip()
    if sha256.startswith("sha256:"):
        sha256 = sha256.removeprefix("sha256:")

    if SHA256_PATTERN.fullmatch(sha256) is None:
        raise RuntimeError(
            f"Invalid SHA-256 for {repository}/{filename}: {sha256!r}"
        )

    encoded_filename = quote(filename, safe="/")
    download_url = f"https://huggingface.co/{repository}/resolve/{resolved_revision}/{encoded_filename}"

    if "/resolve/main/" in download_url:
        raise RuntimeError("Mutable Hugging Face URL generated")

    card_data = getattr(pinned_info, "card_data", None)
    license_id = read_metadata_value(card_data, "license")

    return ResolvedArtifact(
        logicalModelId=logical_model_id,
        applicationModelId=application_model_id,
        repository=repository,
        filename=filename,
        revision=resolved_revision,
        downloadUrl=download_url,
        sizeBytes=size_bytes,
        sha256=sha256,
        quantization=quantization,
        role=role,
        intendedUsage=intended_usage,
        license=license_id if isinstance(license_id, str) else "unknown",
        verificationStatus="huggingface-api-resolved",
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Resolve Hugging Face model metadata for A.U.R.A. catalog."
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Update catalog_sources.json with pinned revisions",
    )
    parser.add_argument(
        "--sources",
        type=Path,
        default=Path("tool/catalog/catalog_sources.json"),
        help="Path to catalog_sources.json",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("build/catalog"),
        help="Directory to store resolved_sources.json",
    )

    args = parser.parse_args()

    if not args.sources.exists():
        print(
            f"Error: Catalog sources file not found: {args.sources}",
            file=sys.stderr,
        )
        return 1

    with open(args.sources, "r", encoding="utf-8") as f:
        sources_data = json.load(f)

    artifacts = sources_data.get("artifacts", [])
    if not artifacts:
        print("Error: No artifacts found in sources", file=sys.stderr)
        return 1

    api = HfApi()
    resolved_list: list[ResolvedArtifact] = []

    print(
        f"Resolving Hugging Face metadata for {len(artifacts)} artifacts..."
    )

    for item in artifacts:
        print(
            f"Resolving {item['logicalModelId']} ({item['repository']} / {item['filename']})..."
        )
        resolved = resolve_artifact(api, item)
        resolved_list.append(resolved)
        print(f" -> Pinned SHA: {resolved.revision}")
        print(f" -> Size: {resolved.sizeBytes} bytes")
        print(f" -> SHA-256: {resolved.sha256}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    resolved_file = args.output_dir / "resolved_sources.json"

    resolved_json = {
        "catalogId": sources_data.get(
            "catalogId", "aura-official-development"
        ),
        "resolvedAt": "2026-07-27T18:35:00Z",
        "artifacts": [asdict(r) for r in resolved_list],
    }

    with open(resolved_file, "w", encoding="utf-8") as f:
        json.dump(resolved_json, f, indent=2)

    print(f"Metadata resolved successfully -> {resolved_file}")

    if args.write:
        for orig, res in zip(artifacts, resolved_list):
            orig["revision"] = res.revision

        with open(args.sources, "w", encoding="utf-8") as f:
            json.dump(sources_data, f, indent=2)
        print(f"Updated {args.sources} with pinned revisions.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
