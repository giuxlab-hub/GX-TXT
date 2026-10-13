#!/usr/bin/env python3
"""Tint the white GNUplot canvas in an already rendered PNG without redrawing data."""
import re
import sys
from PIL import Image


def main():
    source, target, color = sys.argv[1:4]
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        raise ValueError("Plot background must be #RRGGBB")
    background = tuple(int(color[index:index + 2], 16) for index in (1, 3, 5))
    with Image.open(source) as original:
        image = original.convert("RGB")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue = pixels[x, y]
            if max(red, green, blue) - min(red, green, blue) <= 2 and min(red, green, blue) >= 235:
                shade = (red + green + blue) / (3 * 255)
                pixels[x, y] = tuple(round(channel * shade) for channel in background)
    image.save(target, format="PNG")


if __name__ == "__main__":
    main()
