import struct, zlib, sys

with open(sys.argv[1], 'rb') as f:
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
    transparent = semi = total = 0
    offset = 0
    for row in range(h):
        offset += 1
        for col in range(w):
            a = raw[offset+3]
            offset += 4
            total += 1
            if a == 0:
                transparent += 1
            elif a < 255:
                semi += 1
    opaque = total - transparent - semi
    print(f'Total: {total}, Transparent: {transparent} ({transparent*100/total:.1f}%), Semi: {semi} ({semi*100/total:.1f}%), Opaque: {opaque} ({opaque*100/total:.1f}%)')