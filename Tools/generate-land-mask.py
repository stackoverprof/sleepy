#!/usr/bin/env python3
"""Generate Sources/SleepyCore/WorldLandMaskData.swift from Natural Earth land data.

The land outlines come from the world-atlas TopoJSON build of Natural Earth
110m land, which is in the public domain. The script rasterizes them into a
half-degree land/ocean bitmask, deflates it, and writes the base64 payload that
WorldLandMask decodes at runtime.

Usage:
    python3 Tools/generate-land-mask.py [path-or-url-to-land-110m.json]
"""

import base64
import json
import os
import sys
import urllib.request
import zlib

SOURCE = "https://cdn.jsdelivr.net/npm/world-atlas@2/land-110m.json"
STEP = 0.5
COLUMNS = int(360 / STEP)
ROWS = int(180 / STEP)
OUTPUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Sources/SleepyCore/WorldLandMaskData.swift",
)


def load_topology(source):
    if source.startswith("http"):
        with urllib.request.urlopen(source, timeout=60) as response:
            return json.load(response)
    with open(source) as handle:
        return json.load(handle)


def land_rings(topology):
    scale_x, scale_y = topology["transform"]["scale"]
    translate_x, translate_y = topology["transform"]["translate"]

    arcs = []
    for arc in topology["arcs"]:
        x = y = 0
        points = []
        for dx, dy in arc:
            x += dx
            y += dy
            points.append((x * scale_x + translate_x, y * scale_y + translate_y))
        arcs.append(points)

    def ring(indices):
        points = []
        for index in indices:
            arc = arcs[index] if index >= 0 else arcs[-index - 1][::-1]
            points.extend(arc[1:] if points else arc)
        return points

    rings = []
    for geometry in topology["objects"]["land"]["geometries"]:
        polygons = (
            geometry["arcs"]
            if geometry["type"] == "MultiPolygon"
            else [geometry["arcs"]]
        )
        for polygon in polygons:
            for indices in polygon:
                rings.append(ring(indices))
    return rings


def unwrap(ring):
    """Make longitudes continuous so a ring that crosses the antimeridian
    stays one polygon instead of jumping the width of the world."""
    points = [ring[0]]
    offset = 0.0
    for index in range(1, len(ring) + 1):
        x, y = ring[index % len(ring)]
        previous = points[-1][0]
        while x + offset - previous > 180:
            offset -= 360
        while x + offset - previous < -180:
            offset += 360
        points.append((x + offset, y))
    return points


def rasterize(rings):
    # Each ring is filled on its own and combined with exclusive or, so holes
    # punch back out and a ring straddling the antimeridian wraps around the
    # grid instead of corrupting the whole scanline.
    ring_edges = []
    for ring in rings:
        points = unwrap(ring)
        edges = []
        for index in range(len(points) - 1):
            x0, y0 = points[index]
            x1, y1 = points[index + 1]
            if y0 != y1:
                edges.append((min(y0, y1), max(y0, y1), x0, y0, x1, y1))
        if edges:
            ring_edges.append(edges)

    mask = bytearray(COLUMNS * ROWS)
    for row in range(ROWS):
        latitude = 90.0 - (row + 0.5) * STEP
        base = row * COLUMNS
        for edges in ring_edges:
            crossings = []
            for low, high, x0, y0, x1, y1 in edges:
                if low <= latitude < high:
                    crossings.append(x0 + (latitude - y0) * (x1 - x0) / (y1 - y0))
            if not crossings:
                continue
            crossings.sort()
            for index in range(0, len(crossings) - 1, 2):
                start, end = crossings[index], crossings[index + 1]
                first = int(round((start + 180.0) / STEP))
                last = int(round((end + 180.0) / STEP))
                if last <= first:
                    # An island narrower than one cell still deserves a pixel.
                    if (end - start) > STEP * 0.35:
                        mask[base + first % COLUMNS] ^= 1
                    continue
                for column in range(first, last):
                    mask[base + column % COLUMNS] ^= 1

    # Natural Earth stops Antarctica at 85.6S, so close the polar cap by hand.
    cap_row = int((90.0 + 85.5) / STEP)
    for row in range(cap_row, ROWS):
        for column in range(COLUMNS):
            mask[row * COLUMNS + column] = 1

    return mask


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else SOURCE
    mask = rasterize(land_rings(load_topology(source)))

    packed = bytearray((len(mask) + 7) // 8)
    for index, value in enumerate(mask):
        if value:
            packed[index >> 3] |= 0x80 >> (index & 7)

    deflate = zlib.compressobj(9, zlib.DEFLATED, -15)
    payload = base64.b64encode(deflate.compress(bytes(packed)) + deflate.flush()).decode()
    chunks = [payload[start:start + 76] for start in range(0, len(payload), 76)]
    literal = "\n".join('        "%s",' % chunk for chunk in chunks)

    with open(OUTPUT, "w") as handle:
        handle.write(
            """// Generated by Tools/generate-land-mask.py. Do not edit by hand.
//
// Natural Earth 110m land outlines (public domain) rasterized to a
// %d x %d land/ocean bitmask, raw-deflated and base64 encoded.

enum WorldLandMaskData {
    static let columns = %d
    static let rows = %d

    static let deflatedBitmap = [
%s
    ].joined()
}
"""
            % (COLUMNS, ROWS, COLUMNS, ROWS, literal)
        )

    land = sum(mask)
    print(
        "wrote %s (%d land cells of %d, %d base64 characters)"
        % (OUTPUT, land, len(mask), len(payload))
    )


if __name__ == "__main__":
    main()
