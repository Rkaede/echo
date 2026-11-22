#!/usr/bin/env python3
"""Draw Echo's app icons and menu bar icon into echo/Assets.xcassets.

    scripts/make-icons.py

The art follows the "Echo app icon" page of the Echo Onboarding Redesign canvas: a
squircle with the "Speech" waveform, in three colourways.

- Line:  Echo red on near-white (the app icon, AppIcon)
- Red:   white on Echo red (AppIconRed)
- Night: Echo red on near-black (AppIconNight)

Line, Red and Night are each written as an app icon set (AppIconLine, AppIconRed,
AppIconNight) so a future setting can switch between them. AppIcon is a copy of Line, and
it is the one the build uses. The menu bar icon (MenuBarIcon) is a simpler waveform,
"Gentle" (two smooth swings, thicker line), as a one-colour vector template image, so macOS
tints it for light and dark menu bars.

Needs rsvg-convert (brew install librsvg).
"""

import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "echo" / "Assets.xcassets"

RED = "#E1535F"
WHITE = "#FFFFFF"

# name -> (gradient top, gradient bottom, waveform colour)
STYLES = {
    "Line": ("#FFFFFF", "#ECECEC", RED),
    "Red": ("#EC6B76", "#D5434F", WHITE),
    "Night": ("#2C2C30", "#141416", RED),
}

# The "Speech" waveform: four cycles under a speech-like envelope.
AMPLITUDE = 0.72
CYCLES = 4
ICON_STROKE = 30

# The menu bar's "Gentle" waveform: two smooth swings, which still read at 22×16 pt.
GLYPH_AMPLITUDE = 0.62
GLYPH_CYCLES = 2
GLYPH_STROKE = 3.6


def speech_envelope(t: float) -> float:
    return math.sin(math.pi * t) ** 1.1 * (
        0.45 + 0.55 * abs(math.sin(math.pi * 2 * (1.7 * t + 0.07)))
    )


def sine_envelope(t: float) -> float:
    return math.sin(math.pi * t) ** 1.3


def wave_path(
    x0: float, x1: float, cy: float, amp: float, steps: int,
    cycles: float = CYCLES, envelope=speech_envelope,
) -> str:
    points = []
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t
        y = cy + amp * envelope(t) * math.sin(t * cycles * math.pi * 2)
        points.append(f"{'L' if i else 'M'}{x:.2f} {y:.2f}")
    return " ".join(points)


def squircle_path() -> str:
    """A superellipse (n = 5) 824 wide, centred on the 1024 canvas, as on the canvas."""
    n, a, c = 5, 412, 512
    points = []
    for i in range(161):
        t = i / 160 * math.pi * 2
        ct, st = math.cos(t), math.sin(t)
        x = c + a * math.copysign(abs(ct) ** (2 / n), ct)
        y = c + a * math.copysign(abs(st) ** (2 / n), st)
        points.append(f"{'L' if i else 'M'}{x:.1f} {y:.1f}")
    return " ".join(points) + " Z"


def icon_svg(top: str, bottom: str, stroke: str) -> str:
    sq = squircle_path()
    wave = wave_path(232, 792, 512, AMPLITUDE * 280, 140)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>
</linearGradient>
<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
<feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.22"/>
</filter>
</defs>
<path d="{sq}" fill="url(#bg)" filter="url(#shadow)"/>
<path d="{sq}" fill="none" stroke="rgba(0,0,0,0.08)" stroke-width="4"/>
<path d="{wave}" fill="none" stroke="{stroke}" stroke-width="{ICON_STROKE}" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
"""


def glyph_svg() -> str:
    wave = wave_path(4, 40, 16, GLYPH_AMPLITUDE * 14, 72, GLYPH_CYCLES, sine_envelope)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="22" height="16" viewBox="0 0 44 32">
<path d="{wave}" fill="none" stroke="#000" stroke-width="{GLYPH_STROKE}" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
"""


def rsvg(svg: Path, out: Path, *args: str) -> None:
    subprocess.run(["rsvg-convert", *args, "-o", str(out), str(svg)], check=True)


# macOS app icon slots: (point size, scale)
SLOTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def write_app_icon_set(name: str, svg: Path) -> None:
    folder = ASSETS / f"{name}.appiconset"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    images = []
    for points, scale in SLOTS:
        px = points * scale
        filename = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        rsvg(svg, folder / filename, "-w", str(px), "-h", str(px))
        images.append({"filename": filename, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def write_menu_bar_icon(svg: Path) -> None:
    folder = ASSETS / "MenuBarIcon.imageset"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    rsvg(svg, folder / "MenuBarIcon.pdf", "-f", "pdf")
    contents = {
        "images": [{"filename": "MenuBarIcon.pdf", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        for name, (top, bottom, stroke) in STYLES.items():
            svg = tmp_dir / f"{name}.svg"
            svg.write_text(icon_svg(top, bottom, stroke))
            write_app_icon_set(f"AppIcon{name}", svg)
            if name == "Line":
                write_app_icon_set("AppIcon", svg)
        glyph = tmp_dir / "glyph.svg"
        glyph.write_text(glyph_svg())
        write_menu_bar_icon(glyph)
    print(f"Wrote AppIcon, AppIconLine, AppIconRed, AppIconNight and MenuBarIcon to {ASSETS}")


if __name__ == "__main__":
    main()
