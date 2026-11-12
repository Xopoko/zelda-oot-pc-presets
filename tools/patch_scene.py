"""Raise the verified e0f3ccfa scene-width cap, in an installer-owned copy only.

This is a byte recipe, not a game image or binary diff payload.
"""
import argparse
import hashlib
import json
import os
import struct
from pathlib import Path

SIZE = 100_794_368
OFFSET = 0x03F78570
ORIGINAL = "f77dd8d6448b4204ae2be6c91872f6a3ca4ae64fc6566e7b3ed0c3b908d98ee2"
PATCHED = "8aff5492abc56fd237f09d7526d4c346e9a80911f41ba510b600ace08c6c5872"


def patch(path: Path) -> dict:
    data = bytearray(path.read_bytes())
    digest = hashlib.sha256(data).hexdigest()
    if len(data) != SIZE or digest not in (ORIGINAL, PATCHED):
        raise ValueError("Unsupported image.bin. Expected Hookshot 2.1.0 / guest e0f3ccfa; nothing was changed.")
    already = digest == PATCHED
    if not already:
        if struct.unpack_from("<II", data, OFFSET) != (3840, 2160):
            raise ValueError("The verified scene-cap row differs; nothing was changed.")
        struct.pack_into("<I", data, OFFSET, 5120)
    if hashlib.sha256(data).hexdigest() != PATCHED:
        raise ValueError("Patched image digest differs; nothing was changed.")
    if not already:
        temp = path.with_name(path.name + ".width-patch.tmp")
        with temp.open("xb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temp, path)
    return {"guestBuild": "e0f3ccfa", "offset": hex(OFFSET), "widthBefore": 3840,
            "widthAfter": 5120, "heightCap": 2160, "sourceSha256": ORIGINAL,
            "sha256": PATCHED, "alreadyPatched": already}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    result = patch(args.image)
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("Scene cap verified: 5120 x 2160 (requested output is selected separately).")
