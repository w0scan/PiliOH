#!/usr/bin/env python3
"""Composite a transparent PNG icon onto a white background for OHOS."""
from PIL import Image
import sys

if __name__ == '__main__':
    src = sys.argv[1]
    dst = sys.argv[2]
    foreground = Image.open(src).convert('RGBA')
    w, h = foreground.size
    background = Image.new('RGBA', (w, h), (255, 255, 255, 255))
    background.paste(foreground, (0, 0), foreground)
    background = background.convert('RGB')
    background.save(dst, 'PNG')
    print(f'Created {w}x{h} icon with white background: {dst}')