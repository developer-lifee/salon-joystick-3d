#!/usr/bin/env python3
"""Genera las texturas PBR (albedo+rugosidad y normal+altura) del piso y los muros.

Todo es procedural y periódico (ruido filtrado por FFT), así que las texturas repiten
sin costuras. Escribe PNG en Assets.xcassets como Data Sets que el renderer carga con
NSDataAsset:

    python3 Tools/PBRTextures/generate_pbr_textures.py

Canales:
    *AlbedoRough.png  RGB = albedo (sRGB), A = rugosidad
    *NormalHeight.png RGB = normal tangente (0..1),  A = altura
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 1024
ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "Assets.xcassets"
rng = np.random.default_rng(20261113)


def periodic_noise(size, beta, low_cut=1.0):
    """Ruido 1/f^beta periódico (tileable), normalizado a [0, 1]."""
    white = rng.standard_normal((size, size))
    fx = np.fft.fftfreq(size)[None, :] * size
    fy = np.fft.fftfreq(size)[:, None] * size
    radius = np.sqrt(fx * fx + fy * fy)
    radius[0, 0] = 1.0
    spectrum = np.fft.fft2(white) / np.power(np.maximum(radius, low_cut), beta)
    spectrum[0, 0] = 0
    field = np.real(np.fft.ifft2(spectrum))
    field -= field.min()
    return field / max(field.max(), 1e-9)


def fbm(size, octaves):
    total = np.zeros((size, size))
    weight_sum = 0.0
    for beta, low_cut, weight in octaves:
        total += periodic_noise(size, beta, low_cut) * weight
        weight_sum += weight
    return total / weight_sum


def stretched_noise(size, stretch, beta):
    """Ruido alargado en X (vetas de madera del encofrado), también periódico."""
    white = rng.standard_normal((size, size))
    fx = np.fft.fftfreq(size)[None, :] * size * stretch
    fy = np.fft.fftfreq(size)[:, None] * size
    radius = np.sqrt(fx * fx + fy * fy)
    radius[0, 0] = 1.0
    spectrum = np.fft.fft2(white) / np.power(radius, beta)
    spectrum[0, 0] = 0
    field = np.real(np.fft.ifft2(spectrum))
    field -= field.min()
    return field / max(field.max(), 1e-9)


def normal_from_height(height, strength):
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nx, ny, nz = -dx * strength, -dy * strength, np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / length, ny / length, nz / length], axis=-1)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def save_dataset(name, rgba):
    folder = ASSETS / f"{name}.dataset"
    folder.mkdir(parents=True, exist_ok=True)
    image = Image.fromarray(np.clip(rgba * 255.0 + 0.5, 0, 255).astype(np.uint8))
    image.save(folder / f"{name}.png", optimize=True)
    contents = {"data": [{"filename": f"{name}.png", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1}}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def floor_slate_tiles():
    """Losas de pizarra 2x2 (cada losa = 1/2.2 m, como la rejilla del shader)."""
    u = (np.arange(SIZE) + 0.5) / SIZE * 2.0
    tu, tv = np.meshgrid(u, u)
    tile_id = (np.floor(tu) + 2 * np.floor(tv)).astype(int)
    fu, fv = tu % 1.0, tv % 1.0
    edge = np.minimum(np.minimum(fu, 1 - fu), np.minimum(fv, 1 - fv))

    grout_width, bevel = 0.022, 0.03
    grout = edge < grout_width
    bevel_mask = np.clip((edge - grout_width) / bevel, 0, 1)

    grain = fbm(SIZE, [(1.6, 2, 1.0), (1.2, 16, 0.6), (0.8, 64, 0.35)])
    cleft = periodic_noise(SIZE, 2.2, 3)
    layering = np.sin((tu * 3.1 + cleft * 5.0) * np.pi) * 0.5 + 0.5
    speckle = (periodic_noise(SIZE, 0.2) > 0.78).astype(float)

    tile_tint = np.array([[0.105, 0.125, 0.145], [0.12, 0.13, 0.14],
                          [0.095, 0.115, 0.135], [0.115, 0.125, 0.15]])
    base = tile_tint[tile_id % 4]
    variation = (0.78 + 0.32 * grain + 0.12 * layering)[..., None]
    albedo = base * variation + speckle[..., None] * 0.035
    grout_color = np.array([0.055, 0.058, 0.062]) * (0.8 + 0.4 * grain[..., None])
    albedo = np.where(grout[..., None], grout_color, albedo)

    height = np.where(grout, 0.0, 0.55 + 0.45 * bevel_mask) + (grain - 0.5) * 0.06 + layering * 0.04
    roughness = np.where(grout, 0.92, 0.42 + 0.22 * grain + 0.12 * layering)

    normal = normal_from_height(height, strength=SIZE / 90.0)
    save_dataset("PBRFloorAlbedoRough", np.dstack([linear_to_srgb(albedo), roughness]))
    save_dataset("PBRFloorNormalHeight", np.dstack([normal * 0.5 + 0.5, height]))


def wall_board_concrete():
    """Concreto con marcas de tablas de encofrado, poros y huecos de amarre (tile = 2 m)."""
    v = (np.arange(SIZE) + 0.5) / SIZE
    _, gv = np.meshgrid(v, v)
    boards = 10
    board_id = np.floor(gv * boards).astype(int)
    board_frac = (gv * boards) % 1.0
    board_edge = np.minimum(board_frac, 1 - board_frac)

    wood = stretched_noise(SIZE, 16, 1.4)
    cloud = fbm(SIZE, [(2.0, 1, 1.0), (1.4, 8, 0.5)])
    fine = periodic_noise(SIZE, 0.6)
    pores = (periodic_noise(SIZE, 0.1) > 0.86).astype(float)

    board_shift = rng.uniform(-0.10, 0.10, boards)[board_id]
    seam = np.exp(-board_edge / 0.035)
    tone = 0.88 + 0.24 * cloud + 0.12 * wood + board_shift - seam * 0.18
    albedo = np.array([0.40, 0.40, 0.39])[None, None, :] * tone[..., None]
    albedo *= (1.0 - pores * 0.45)[..., None]
    height = 0.5 + (wood - 0.5) * 0.18 + (fine - 0.5) * 0.08 - seam * 0.12 - pores * 0.25
    roughness = np.clip(0.82 + 0.1 * fine - 0.08 * cloud + pores * 0.1, 0, 1)

    # Huecos de amarre del encofrado (2x2 por tile)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE] / SIZE
    for cx in (0.25, 0.75):
        for cy in (0.25, 0.75):
            d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
            hole = d < 0.012
            ring = np.exp(-((d - 0.016) / 0.006) ** 2)
            height = np.where(hole, 0.1, height - ring * 0.05)
            albedo = np.where(hole[..., None], albedo * 0.35, albedo)

    normal = normal_from_height(height, strength=SIZE / 70.0)
    save_dataset("PBRWallAlbedoRough", np.dstack([linear_to_srgb(albedo), roughness]))
    save_dataset("PBRWallNormalHeight", np.dstack([normal * 0.5 + 0.5, np.clip(height, 0, 1)]))


if __name__ == "__main__":
    floor_slate_tiles()
    wall_board_concrete()
    for path in sorted(ASSETS.glob("PBR*.dataset/*.png")):
        print(f"{path.relative_to(ROOT)}  {path.stat().st_size / 1e6:.1f} MB")
