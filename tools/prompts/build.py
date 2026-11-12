#!/usr/bin/env python3
"""Build Ocarina 1.1.1 keyboard prompt overrides from a local RomFS."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile

import zstandard
from fontTools.ttLib import TTFont
from PIL import Image, ImageChops

import button_icons as icons


SUFFIX = "Nin_Ounce_NVN2"
DICTIONARY = "Pack/ZsDic.pack.zs"
FONT = f"Font2/Scalable/External.{SUFFIX}.bfotf.zs"
LABEL_FONT = f"Font2/Scalable/ClarimoUDPE-DemiBold.{SUFFIX}.bfotf.zs"
SYMBOL_FONT = f"Font2/Scalable/MotoyaAporoStd-W7.{SUFFIX}.bfotf.zs"
RESTBL = f"System/Resource/ResourceSizeTable.Product.111.{SUFFIX}.rsizetable.zs"
TEXTURES = f"UI/Layout2Archive/Common.Product.100.{SUFFIX}.bntx.zs"
SOURCE_SHA = {
    DICTIONARY: "1f35801d24503905093bb2f6634e5779c1413ca7e6756421160e44d996e60904",
    FONT: "fb371ef34f505da2c16fcac49a764798143cb5368f4e6482fa4d16afaff3d578",
    LABEL_FONT: "c856cba63f7cc60cf31b57c02ea31a4fe5378a60a83c6665cd7c5e0fb53349e5",
    SYMBOL_FONT: "ed474a2151af81b2ffafab7a0614e92baa033705f7dc7aeacc707a0f629354bf",
    RESTBL: "15bd6f03ce65e943fea7e0c2fc7cee2a9548b54f06ba943bc58ebde6b1cac64e",
    TEXTURES: "26c9232bdbf5e2ad3431add5d92c90553f42bbb37aa4d3e901289c8cda5a0186",
}
ATLAS_GLYPHS = {f"KeyTexFont{button}_00": 0xE040 + index for index, button in enumerate("ABXY")}
OCARINA_NOTES = {f"OcarinaButton{button}_00": button for button in "ABXYLR"}
BUTTON_NAMES = {"ls": "LCLICK", "rs": "RCLICK", "move_up": "LSTICK_UP",
                "move_down": "LSTICK_DOWN", "move_left": "LSTICK_LEFT", "move_right": "LSTICK_RIGHT"}
VK_NAMES = {0x01: "mouse_l", 0x02: "mouse_r", 0x04: "mouse_m", 0x05: "mouse_x1", 0x06: "mouse_x2",
            0x08: "backspace", 0x09: "tab", 0x0D: "enter", 0x10: "lshift", 0x11: "lctrl",
            0x12: "lalt", 0x1B: "esc", 0x20: "space", 0x21: "pgup", 0x22: "pgdn",
            0x23: "end", 0x24: "home", 0x25: "left", 0x26: "up", 0x27: "right", 0x28: "down",
            0x2D: "ins", 0x2E: "del",
            0xA0: "lshift", 0xA1: "rshift", 0xA2: "lctrl", 0xA3: "rctrl"}
VK_NAMES.update({0x70 + index: f"f{index + 1}" for index in range(24)})


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_checked(romfs, relative):
    data = (romfs / relative).read_bytes()
    if sha256(data) != SOURCE_SHA[relative]:
        raise ValueError(f"unexpected SHA-256 for {relative}")
    return data


def dict_one(romfs):
    data = zstandard.ZstdDecompressor().decompress(read_checked(romfs, DICTIONARY))
    head, _, size, base = struct.unpack_from("<HHII", data, 4)
    fat, count = struct.unpack_from("<HH", data, head + 4)
    table = head + fat
    names = table + count * 16 + 8
    if data[:4] != b"SARC" or size != len(data):
        raise ValueError("unexpected Zstandard dictionary archive")
    for index in range(count):
        _, name_word, start, end = struct.unpack_from("<IIII", data, table + index * 16)
        name = names + (name_word & 0xFFFFFF) * 4
        if data[name:data.index(0, name, base)] == b"zs.zsdic":
            dictionary = zstandard.ZstdCompressionDict(data[base + start:base + end])
            if dictionary.dict_id() != 1:
                raise ValueError("unexpected UI dictionary ID")
            return dictionary
    raise ValueError("UI dictionary missing")


def current_binds(path):
    binds = dict(icons.PC_BINDS)
    binds.update(CAM_LEFT="left", CAM_RIGHT="right")
    # Prefer physical mouse buttons for these two actions when both work.
    for name, first, second in re.findall(r"^key_(\w+)=([0-9]+),([0-9]+)$", path.read_text(encoding="utf-8-sig"), re.M):
        button = BUTTON_NAMES.get(name, name.upper())
        if button not in binds:
            continue
        keys = (int(first), int(second))
        key = next((key for key in keys if key in (1, 2, 4, 5, 6)), keys[0] or keys[1])
        if key == 0:
            binds[button] = "unbound"
        elif 48 <= key <= 57 or 65 <= key <= 90:
            binds[button] = chr(key).lower()
        else:
            if key not in VK_NAMES:
                raise ValueError(f"Unsupported prompt key for {name}: VK {key}. Choose a supported key; see docs/CONTROLS.md.")
            binds[button] = VK_NAMES[key]
    return binds


def add_oot_guide_icons(outlines, advances, drawings, binds):
    def key_strip(cp, names):
        advance = advances[cp]
        width = min(260, (advance - 50 - 20 * (len(names) - 1)) / len(names))
        start = (advance - width * len(names) - 20 * (len(names) - 1)) / 2
        labels = [icons.PC_LABELS.get(binds[name], binds[name].upper()) for name in names]

        def draw(pen):
            for index, label in enumerate(labels):
                x = start + index * (width + 20)
                icons.rounded(pen, x, 175, x + width, 435, 30)
                outlines.hole(pen, label, x + width / 2, 305, 120, width * 0.75)

        drawings[cp] = (advance, draw)

    # Verified labels in EUru StaticMsg/GuideKeyIcon.msbt.
    key_strip(0xE06A, ("LEFT", "DOWN", "RIGHT"))
    key_strip(0xE068, ("CAM_LEFT", "CAM_RIGHT"))


def decode_bc4(block):
    hi, lo = block[:2]
    palette = [hi, lo] + ([(hi * (7 - i) + lo * i) // 7 for i in range(1, 7)] if hi > lo else
                          [(hi * (5 - i) + lo * i) // 5 for i in range(1, 5)] + [0, 255])
    bits = int.from_bytes(block[2:], "little")
    return [palette[(bits >> (3 * i)) & 7] for i in range(16)]


def encode_bc4(pixels):
    hi, lo = max(pixels), min(pixels)
    if hi == lo:
        return bytes((hi, lo)) + b"\0" * 6
    palette = [hi, lo] + [(hi * (7 - i) + lo * i) // 7 for i in range(1, 7)]
    bits = 0
    for index, pixel in enumerate(pixels):
        nearest = min(range(8), key=lambda choice: abs(pixel - palette[choice]))
        bits |= nearest << (3 * index)
    return bytes((hi, lo)) + bits.to_bytes(6, "little")


def ounce_gob(x, y, width_gobs, block_height):
    """Byte offset of a texture with Ounce BRTI storage layout 0x100c9."""
    block_rows = 8 * block_height
    base = ((y // block_rows) * width_gobs + x // 64) * 512 * block_height
    gob = (y % block_rows) // 8 * 512
    return base + gob + (x % 64 // 32) * 256 + (y % 8 // 4) * 128 + (x % 32 // 16) * 64 + (y % 4) * 16 + x % 16


def astc_codec(tool, mode, src, dst, *args):
    subprocess.run([str(tool), mode, str(src), str(dst), *args, "-silent"],
                   check=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def note_ink(button, binds, outlines, drawings):
    key = binds[button]
    if key in icons.PC_MOUSE:
        _, draw = drawings[0xE040 + "ABXYLR".index(button)]
        max_size = (32, 39)
    else:
        label = "SPACE" if key == "space" else icons.PC_LABELS.get(key, key.upper())
        draw = lambda pen: outlines.hole(pen, label, 0, 0, 100, 600)
        max_size = (51, 35)
    mask = Image.frombytes("L", (160, 160), bytes(icons.rasterize(draw, 160)))
    mask = mask.crop(mask.getbbox())
    mask.thumbnail(max_size, Image.Resampling.LANCZOS)
    return mask


def redraw_note(data, tool, temp, button, binds, outlines, drawings):
    blocks = 24
    head = bytes.fromhex("13aba15c0404015d00005d0000010000")
    offsets = [ounce_gob(x * 16, y, 6, 4) for y in range(blocks) for x in range(blocks)]
    if len(set(offsets)) != blocks * blocks or max(offsets) + 16 > len(data):
        raise ValueError(f"invalid ASTC layout for ocarina note {button}")
    stock_astc, stock_png = temp / "stock.astc", temp / "stock.png"
    new_png, new_astc = temp / "new.png", temp / "new.astc"
    check_astc, check_png = temp / "check.astc", temp / "check.png"
    stock_astc.write_bytes(head + b"".join(data[at:at + 16] for at in offsets))
    astc_codec(tool, "-ds", stock_astc, stock_png)
    stock = Image.open(stock_png).convert("RGBA")
    alpha = stock.getchannel("A")
    color = stock.getchannel("R")
    if stock.size != (93, 93) or any(ImageChops.difference(color, stock.getchannel(chan)).getbbox()
                                     for chan in "GB"):
        raise ValueError(f"unexpected ASTC channels for ocarina note {button}")
    old_ink = ImageChops.multiply(color.point(lambda v: 255 if v < 254 else 0),
                                  alpha.point(lambda v: 255 if v == 255 else 0))
    old_box = old_ink.getbbox()
    if not old_box or min(old_box[:2]) < 12 or max(old_box[2:]) > 81:
        raise ValueError(f"unexpected stock letter bounds for ocarina note {button}: {old_box}")
    mask = note_ink(button, binds, outlines, drawings)
    cx = (old_box[0] + old_box[2]) // 2
    cy = (old_box[1] + old_box[3]) // 2
    new_color = color.copy()
    new_color.paste(255, (0, 0), old_ink)
    new_color.paste(0, (cx - mask.width // 2, cy - mask.height // 2), mask)
    diff = ImageChops.difference(color, new_color)
    change = diff.getbbox()
    if not change:
        raise ValueError(f"unchanged ocarina note {button}")
    dirty = []
    for y in range(change[1] // 4, (change[3] + 3) // 4):
        for x in range(change[0] // 4, (change[2] + 3) // 4):
            box = (x * 4, y * 4, x * 4 + 4, y * 4 + 4)
            if not diff.crop(box).getbbox():
                continue
            if alpha.crop(box).getextrema() != (255, 255):
                raise ValueError(f"note {button} ink touches the silhouette: {box}, {alpha.crop(box).getextrema()}")
            dirty.append(y * blocks + x)
    Image.merge("RGBA", (new_color, new_color, new_color, alpha)).save(new_png)
    astc_codec(tool, "-cs", new_png, new_astc, "4x4", "-thorough")
    compressed = new_astc.read_bytes()
    if compressed[:16] != head or len(compressed) != 16 + len(offsets) * 16:
        raise ValueError(f"unexpected encoded ASTC for ocarina note {button}")
    updated = bytearray(data)
    for index in dirty:
        at = offsets[index]
        updated[at:at + 16] = compressed[16 + index * 16:32 + index * 16]
    check_astc.write_bytes(head + b"".join(updated[at:at + 16] for at in offsets))
    astc_codec(tool, "-ds", check_astc, check_png)
    decoded = Image.open(check_png).convert("RGBA")
    if ImageChops.difference(alpha, decoded.getchannel("A")).getbbox():
        raise ValueError(f"changed ASTC silhouette for ocarina note {button}")
    return updated, (stock, decoded)


def redraw_atlas(data, drawings, *, note_tool=None, note_dir=None, binds=None, outlines=None):
    if data[:4] != b"BNTX" or data[0x20:0x24] != b"Ounc":
        raise ValueError("unexpected Switch 2 texture archive")
    output = bytearray(data)
    count, table = struct.unpack_from("<IQ", data, 0x24)
    changed = []
    previews = {}
    for index in range(count):
        info = struct.unpack_from("<Q", data, table + 8 * index)[0]
        name_at = struct.unpack_from("<Q", data, info + 0x60)[0]
        name_length = struct.unpack_from("<H", data, name_at)[0]
        name = data[name_at + 2:name_at + 2 + name_length].decode()
        if name not in ATLAS_GLYPHS and not (note_tool and name in OCARINA_NOTES):
            continue
        mip, fmt = struct.unpack_from("<H", data, info + 0x16)[0], struct.unpack_from("<I", data, info + 0x1C)[0]
        w, h = struct.unpack_from("<II", data, info + 0x24)
        layout, storage = struct.unpack_from("<II", data, info + 0x34)
        byte_count = struct.unpack_from("<I", data, info + 0x50)[0]
        pointers = struct.unpack_from("<Q", data, info + 0x70)[0]
        start = struct.unpack_from("<Q", data, pointers)[0]
        if storage != 0x100C9 or start + byte_count > len(data):
            raise ValueError(f"unexpected Ounce storage metadata for {name}")
        if name in OCARINA_NOTES:
            if (mip, fmt, w, h, layout, byte_count) != (1, 0x2D06, 93, 93, 2, 12288):
                raise ValueError(f"unexpected ASTC note metadata for {name}")
            button = OCARINA_NOTES[name]
            updated, previews[button] = redraw_note(data[start:start + byte_count], note_tool, note_dir,
                                                   button, binds, outlines, drawings)
            output[start:start + byte_count] = updated
            changed.append(name)
            continue
        if (mip, fmt, w, h, layout, byte_count) != (1, 0x1D01, 64, 64, 1, 2048):
            raise ValueError(f"unexpected BC4 mask metadata for {name}")
        mask = icons.rasterize(drawings[ATLAS_GLYPHS[name]][1], w)
        previous = set()
        current = set()
        touched = set()
        for by in range(16):
            for bx in range(16):
                pixels = [mask[(by * 4 + y) * w + bx * 4 + x] for y in range(4) for x in range(4)]
                offset = ounce_gob(bx * 8, by, 2, 2)
                if offset in touched or offset + 8 > byte_count:
                    raise ValueError(f"invalid BC4 swizzle for {name}")
                touched.add(offset)
                block = encode_bc4(pixels)
                previous.update(decode_bc4(data[start + offset:start + offset + 8]))
                current.update(decode_bc4(block))
                output[start + offset:start + offset + 8] = block
        if previous.issubset({0}) or current.issubset({0}) or output[start:start + byte_count] == data[start:start + byte_count]:
            raise ValueError(f"empty or unchanged BC4 mask for {name}")
        changed.append(name)
    expected = set(ATLAS_GLYPHS) | (set(OCARINA_NOTES) if note_tool else set())
    if set(changed) != expected:
        raise ValueError("incomplete action-button atlas")
    return output, changed, previews


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--romfs", type=Path, required=True, help="local Hookshot RomFS folder")
    parser.add_argument("--options", type=Path, required=True, help="Hookshot options INI with key bindings")
    parser.add_argument("--output", type=Path, required=True, help="new mod folder (will contain romfs/)")
    parser.add_argument("--font-only", action="store_true", help="stage the text-glyph test without the HUD atlas")
    parser.add_argument("--astcenc", type=Path, help="ARM astcenc executable for the six ocarina note icons")
    parser.add_argument("--preview", type=Path, help="output a contact sheet of decoded ocarina note icons")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("output folder already exists")
    if not args.romfs.is_dir() or not args.options.is_file():
        parser.error("--romfs and --options must identify the local RomFS and options file")
    if args.astcenc and (args.font_only or not args.astcenc.is_file()):
        parser.error("note atlas requires an existing astcenc executable and texture patching")
    if args.preview and (not args.astcenc or args.preview.exists()):
        parser.error("preview requires --astcenc and a new path")

    romfs = args.romfs
    dictionary = dict_one(romfs)
    ui_decoder = zstandard.ZstdDecompressor(dict_data=dictionary)
    decoder = zstandard.ZstdDecompressor()
    ui_encoder = zstandard.ZstdCompressor(level=15, dict_data=dictionary)
    font_blob = ui_decoder.decompress(read_checked(romfs, FONT))
    outlines = icons.text_glyphs([ui_decoder.decompress(read_checked(romfs, path)) for path in (LABEL_FONT, SYMBOL_FONT)])
    binds = current_binds(args.options)
    icons.PC_LABELS.update(lshift="SHIFT", rshift="SHIFT", unbound="—")
    advances = icons.font_advances(font_blob)
    drawings = icons.pc_icons(outlines, advances, binds)
    add_oot_guide_icons(outlines, advances, drawings, binds)
    binds.pop("SHAKE")  # The TotK shake binding is replaced above by the real camera keys.
    otf, key = icons.bfotf_decode(font_blob)
    updated_otf = icons.redraw_font(otf, drawings)
    updated_font = icons.bfotf_encode(updated_otf, key, font_blob)
    parsed = TTFont(io.BytesIO(icons.bfotf_decode(updated_font)[0]))
    if parsed.getBestCmap() != TTFont(io.BytesIO(otf)).getBestCmap():
        raise ValueError("button font character map changed")
    encoded_font = ui_encoder.compress(updated_font)
    if ui_decoder.decompress(encoded_font) != updated_font:
        raise ValueError("button font failed compression round trip")
    outputs = {FONT: encoded_font}
    growth = len(updated_font) - len(font_blob)
    if growth > 0:
        table = decoder.decompress(read_checked(romfs, RESTBL))
        new_table = icons.grow_restbl(table, {FONT: (growth + 7) & ~7})
        outputs[RESTBL] = zstandard.ZstdCompressor(level=15).compress(new_table)
        if decoder.decompress(outputs[RESTBL]) != new_table:
            raise ValueError("resource table failed compression round trip")
    atlas_names = []
    if not args.font_only:
        atlas = decoder.decompress(read_checked(romfs, TEXTURES))
        with tempfile.TemporaryDirectory() as temp:
            updated_atlas, atlas_names, previews = redraw_atlas(atlas, drawings,
                note_tool=args.astcenc.resolve() if args.astcenc else None, note_dir=Path(temp),
                binds=binds, outlines=outlines)
        outputs[TEXTURES] = zstandard.ZstdCompressor(level=5).compress(updated_atlas)
        if decoder.decompress(outputs[TEXTURES]) != updated_atlas:
            raise ValueError("texture archive failed compression round trip")
        if args.preview:
            sheet = Image.new("RGBA", (6 * 93, 2 * 93), "#353535")
            for index, button in enumerate("ABXYLR"):
                for row, preview in enumerate(previews[button]):
                    sheet.alpha_composite(preview, (index * 93, row * 93))
            sheet.save(args.preview)
    for relative, payload in outputs.items():
        destination = args.output / "romfs" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("xb") as handle:
            handle.write(payload)
    print(json.dumps({
        "mapping": binds, "font_glyphs": [f"U+{cp:04X}" for cp in sorted(drawings)], "atlas_masks": atlas_names,
        "files": {name: {"bytes": len(data), "sha256": sha256(data), "original_sha256": SOURCE_SHA[name]}
                  for name, data in outputs.items()},
    }, indent=2))


if __name__ == "__main__":
    main()
