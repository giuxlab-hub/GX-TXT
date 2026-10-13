#!/usr/bin/env python3
"""Temporary display scaling and full-resolution selection crop for the GX plot viewer."""
import sys
from PIL import Image


def main():
    mode, source, target, *values = sys.argv[1:]
    with Image.open(source) as image:
        if mode == "scale":
            factor = float(values[0])
            size = (max(1, round(image.width * factor)), max(1, round(image.height * factor)))
            image.resize(size, Image.Resampling.LANCZOS).save(target, format="PNG")
        elif mode == "crop":
            x0, y0, x1, y1 = map(int, values)
            if not (0 <= x0 < x1 <= image.width and 0 <= y0 < y1 <= image.height):
                raise ValueError("Selection is outside the image")
            image.crop((x0, y0, x1, y1)).save(target, format="PNG")
        else:
            raise ValueError("Unknown viewer raster action")


if __name__ == "__main__":
    main()
