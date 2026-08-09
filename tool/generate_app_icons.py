import json
import sys
from pathlib import Path

from PIL import Image


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_app_icons.py SOURCE_PNG")

    root = Path(__file__).resolve().parents[1]
    source_path = Path(sys.argv[1]).resolve()
    with Image.open(source_path) as opened:
        source = opened.convert("RGB")

    if source.width != source.height or source.width < 1024:
        raise SystemExit(f"source must be square and at least 1024px, got {source.size}")
    source = source.resize((1024, 1024), Image.Resampling.LANCZOS)

    icon_dir = root / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((icon_dir / "Contents.json").read_text(encoding="utf-8"))
    for item in contents["images"]:
        filename = item.get("filename")
        if not filename:
            continue
        points = float(item["size"].split("x", 1)[0])
        scale = int(item["scale"].removesuffix("x"))
        pixels = round(points * scale)
        source.resize((pixels, pixels), Image.Resampling.LANCZOS).save(
            icon_dir / filename, format="PNG", optimize=True
        )

    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    res_dir = root / "android" / "app" / "src" / "main" / "res"
    for folder, pixels in android_sizes.items():
        source.resize((pixels, pixels), Image.Resampling.LANCZOS).save(
            res_dir / folder / "ic_launcher.png", format="PNG", optimize=True
        )


if __name__ == "__main__":
    main()
