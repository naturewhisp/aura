from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path


def download_and_verify(
    logical_id: str,
    resolved_sources_file: Path,
    target_dir: Path,
    keep_downloaded: bool = True,
) -> int:
    if not resolved_sources_file.exists():
        print(
            f"Error: Resolved sources file not found: {resolved_sources_file}",
            file=sys.stderr,
        )
        return 1

    with open(resolved_sources_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    artifacts = data.get("artifacts", [])
    target_artifact = next(
        (a for a in artifacts if a.get("logicalModelId") == logical_id), None
    )

    if not target_artifact:
        print(
            f"Error: Artifact '{logical_id}' not found in resolved_sources.json",
            file=sys.stderr,
        )
        return 1

    url = target_artifact["downloadUrl"]
    expected_size = target_artifact["sizeBytes"]
    expected_sha256 = target_artifact["sha256"].lower().strip()
    filename = target_artifact["filename"]

    target_dir.mkdir(parents=True, exist_ok=True)
    final_file = target_dir / filename
    temp_file = target_dir / f"{filename}.tmp"

    print(f"Downloading artifact '{logical_id}' from {url}...")
    print(f"Target file: {final_file}")
    print(f"Expected Size: {expected_size} bytes")
    print(f"Expected SHA-256: {expected_sha256}")

    req = urllib.request.Request(
        url,
        headers={"User-Agent": "AURA-Catalog-Tooling/1.0"},
    )

    hasher = hashlib.sha256()
    downloaded_bytes = 0

    try:
        with urllib.request.urlopen(req, timeout=60) as response, open(
            temp_file, "wb"
        ) as out_f:
            chunk_size = 1024 * 1024  # 1 MB
            while True:
                chunk = response.read(chunk_size)
                if not chunk:
                    break
                out_f.write(chunk)
                hasher.update(chunk)
                downloaded_bytes += len(chunk)
                mb = downloaded_bytes / (1024 * 1024)
                pct = (
                    (downloaded_bytes / expected_size * 100)
                    if expected_size > 0
                    else 0
                )
                sys.stdout.write(f"\rProgress: {mb:.2f} MB ({pct:.1f}%)")
                sys.stdout.flush()

        print()  # Newline after progress

    except Exception as e:
        print(f"\nDownload failed: {e}", file=sys.stderr)
        if temp_file.exists():
            temp_file.unlink()
        return 1

    actual_sha256 = hasher.hexdigest().lower().strip()

    print(f"Downloaded Size: {downloaded_bytes} bytes")
    print(f"Computed SHA-256: {actual_sha256}")

    if downloaded_bytes != expected_size:
        print(
            f"Error: Size mismatch! Expected {expected_size}, got {downloaded_bytes}",
            file=sys.stderr,
        )
        if temp_file.exists():
            temp_file.unlink()
        return 1

    if actual_sha256 != expected_sha256:
        print(
            f"Error: SHA-256 mismatch! Expected {expected_sha256}, got {actual_sha256}",
            file=sys.stderr,
        )
        if temp_file.exists():
            temp_file.unlink()
        return 1

    if temp_file.exists():
        if final_file.exists():
            final_file.unlink()
        temp_file.rename(final_file)

    print(
        f"Verification Successful! Artifact saved to {final_file}"
    )

    # Update verification status in resolved_sources.json
    target_artifact["verificationStatus"] = (
        "locally-downloaded-and-verified"
    )
    with open(resolved_sources_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    if not keep_downloaded:
        print("Cleaning up temporary downloaded file as requested...")
        if final_file.exists():
            final_file.unlink()

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Download and verify an artifact locally."
    )
    parser.add_argument(
        "--logical-id",
        type=str,
        default="qwen2.5-0.5b-instruct-download-test-q4_0",
        help="Logical model ID to download and verify",
    )
    parser.add_argument(
        "--resolved-sources",
        type=Path,
        default=Path("build/catalog/resolved_sources.json"),
        help="Path to resolved_sources.json",
    )
    parser.add_argument(
        "--target-dir",
        type=Path,
        default=Path(".local/download-test"),
        help="Directory to download the file to",
    )
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="Remove downloaded file after verification",
    )

    args = parser.parse_args()

    return download_and_verify(
        args.logical_id,
        args.resolved_sources,
        args.target_dir,
        keep_downloaded=not args.cleanup,
    )


if __name__ == "__main__":
    sys.exit(main())
