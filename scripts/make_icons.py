"""Generate the extension's PNG icons (blue rounded square, white double check).

Pure standard library so it runs anywhere: python3 scripts/make_icons.py
"""
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "extension" / "icons"
BLUE = (10, 102, 194)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    cx, cy = ax + t * dx, ay + t * dy
    return ((px - cx) ** 2 + (py - cy) ** 2) ** 0.5


def coverage(fn, x, y, n=4):
    hits = 0
    for i in range(n):
        for j in range(n):
            if fn(x + (i + 0.5) / n, y + (j + 0.5) / n):
                hits += 1
    return hits / (n * n)


def render(size):
    s = size
    r = s * 0.22  # corner radius

    def in_rect(px, py):
        qx = max(abs(px - s / 2) - (s / 2 - r), 0)
        qy = max(abs(py - s / 2) - (s / 2 - r), 0)
        return qx * qx + qy * qy <= r * r

    w = max(s * 0.085, 1.2)  # stroke half-width
    # Two check marks ("read all"), in unit coordinates.
    checks = [
        [(0.16, 0.55), (0.33, 0.71), (0.62, 0.36)],
        [(0.42, 0.66), (0.47, 0.71), (0.84, 0.30)],
    ]

    def in_check(px, py):
        for pts in checks:
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                if seg_dist(px, py, ax * s, ay * s, bx * s, by * s) <= w:
                    return True
        return False

    rows = []
    for y in range(s):
        row = bytearray([0])
        for x in range(s):
            a = coverage(in_rect, x, y)
            c = coverage(in_check, x, y) if a else 0
            rgb = [round(BLUE[k] * (1 - c) + 255 * c) for k in range(3)]
            row += bytes(rgb + [round(255 * a)])
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", s, s, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for size in (16, 32, 48, 128):
        (OUT / f"icon{size}.png").write_bytes(render(size))
        print("wrote", OUT / f"icon{size}.png")
