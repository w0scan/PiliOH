#!/usr/bin/env python3
"""Composite a transparent PNG icon onto a white background for OHOS."""
import struct, zlib, sys

def read_png_pixels(path):
    with open(path, 'rb') as f:
        sig = f.read(8)
        idat_chunks = []
        w = h = 0
        while True:
            chunk_len = struct.unpack('>I', f.read(4))[0]
            chunk_type = f.read(4).decode('ascii')
            chunk_data = f.read(chunk_len)
            chunk_crc = f.read(4)
            if chunk_type == 'IHDR':
                w, h = struct.unpack('>II', chunk_data[:8])
            if chunk_type == 'IDAT':
                idat_chunks.append(chunk_data)
            if chunk_type == 'IEND':
                break
        raw = zlib.decompress(b''.join(idat_chunks))
        pixels = []
        offset = 0
        for row in range(h):
            offset += 1  # skip filter byte
            for col in range(w):
                r, g, b, a = raw[offset], raw[offset+1], raw[offset+2], raw[offset+3]
                pixels.append((r, g, b, a))
                offset += 4
    return w, h, pixels

def make_png_rgb(width, height, pixels_list):
    def chunk(ctype, data):
        c = ctype.encode('ascii') + data
        crc = struct.pack('>I', zlib.crc32(c) & 0xffffffff)
        return struct.pack('>I', len(data)) + c + crc
    
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)  # 8bit RGB
    
    raw_data = bytearray()
    for row in range(height):
        raw_data.append(0)  # filter none
        for col in range(width):
            idx = row * width + col
            r, g, b, a = pixels_list[idx]
            raw_data.extend([r, g, b])
    
    compressed = zlib.compress(bytes(raw_data))
    return sig + chunk('IHDR', ihdr) + chunk('IDAT', compressed) + chunk('IEND', b'')

def composite_on_white(w, h, pixels):
    out = []
    for r, g, b, a in pixels:
        alpha = a / 255.0
        out_r = int(r * alpha + 255 * (1 - alpha))
        out_g = int(g * alpha + 255 * (1 - alpha))
        out_b = int(b * alpha + 255 * (1 - alpha))
        out.append((out_r, out_g, out_b, 255))
    return out

if __name__ == '__main__':
    src = sys.argv[1]
    dst = sys.argv[2]
    w, h, pixels = read_png_pixels(src)
    out_pixels = composite_on_white(w, h, pixels)
    png_data = make_png_rgb(w, h, out_pixels)
    with open(dst, 'wb') as f:
        f.write(png_data)
    print(f'Created {w}x{h} icon with white background: {dst}')