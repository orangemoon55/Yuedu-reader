#!/usr/bin/env python3
"""Mach-O metadata checks shared by local verification and macOS packaging."""
from pathlib import Path
import plistlib
import shutil
import struct

MACH_MAGICS = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}


def version_tuple(value):
    return (value >> 16, (value >> 8) & 255, value & 255)


def inspect_binary(path):
    """Read load commands only; never read the application code or configuration."""
    result = []
    with Path(path).open('rb') as f:
        magic = f.read(4)
        if magic not in MACH_MAGICS:
            return []
        if magic in (b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'):
            endian = '>' if magic[0] == 0xca else '<'
            count = struct.unpack(endian + 'I', f.read(4))[0]
            if count > 32:
                raise ValueError('Mach-O 架构数量不正确：' + Path(path).name)
            wide = magic in (b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')
            fmt = endian + ('IIQQII' if wide else 'IIIII')
            slices = [struct.unpack(fmt, f.read(struct.calcsize(fmt)))[2] for _ in range(count)]
        else:
            slices = [0]
        for offset in slices:
            f.seek(offset)
            header = f.read(32)
            endian = '<' if header[:4] == b'\xcf\xfa\xed\xfe' else '>'
            if header[:4] not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
                raise ValueError('不支持的 Mach-O 架构：' + Path(path).name)
            _, cpu, subtype, kind, count, size, flags, _ = struct.unpack(endian + '8I', header)
            if count > 8192 or size > 8 * 1024 * 1024:
                raise ValueError('Mach-O 指令区过大：' + Path(path).name)
            commands = f.read(size)
            item = dict(cpu=cpu, subtype=subtype, kind=kind, minimums=[], platforms=[], dependencies=[], identifier=None, text_size=0, symbols=None)
            cursor = 0
            for _ in range(count):
                cmd, length = struct.unpack_from(endian + 'II', commands, cursor)
                if length < 8 or cursor + length > len(commands):
                    raise ValueError('Mach-O 指令损坏：' + Path(path).name)
                block = commands[cursor:cursor + length]
                if cmd == 0x32:
                    platform, minimum = struct.unpack_from(endian + 'II', block, 8)
                    item['platforms'].append(platform)
                    item['minimums'].append(version_tuple(minimum))
                elif cmd == 0x25:
                    item['platforms'].append(2)
                    item['minimums'].append(version_tuple(struct.unpack_from(endian + 'I', block, 8)[0]))
                elif cmd in (0xc, 0x80000018, 0x8000001f, 0x80000023, 0x20, 0xd):
                    start = struct.unpack_from(endian + 'I', block, 8)[0]
                    value = block[start:].split(b'\0', 1)[0].decode('utf-8')
                    if cmd == 0xd:
                        item['identifier'] = value
                    else:
                        item['dependencies'].append(value)
                elif cmd == 0x19:
                    sections = struct.unpack_from(endian + 'I', block, 64)[0]
                    for n in range(sections):
                        pos = 72 + 80 * n
                        name = block[pos:pos + 16].split(b'\0', 1)[0]
                        if name == b'__text':
                            item['text_size'] += struct.unpack_from(endian + 'Q', block, pos + 40)[0]
                elif cmd == 2:
                    item['symbols'] = struct.unpack_from(endian + 'I', block, 12)[0]
                cursor += length
            result.append(item)
    return result


def binaries(root):
    for path in Path(root).rglob('*'):
        if path.is_file() and not path.is_symlink():
            slices = inspect_binary(path)
            if slices:
                yield path, slices


def clean_unused_stubs(app):
    """Xcode injects iOS100 dylibs into codeless static-library frameworks. Remove
    only empty stubs with no incoming load commands; never lower deployment versions."""
    app = Path(app)
    images = list(binaries(app))
    references = {name for _, slices in images for sl in slices for name in sl['dependencies']}
    removed = []
    for framework in sorted((app / 'Frameworks').glob('*.framework')):
        info = plistlib.loads((framework / 'Info.plist').read_bytes())
        executable = framework / info.get('CFBundleExecutable', framework.stem)
        slices = inspect_binary(executable)
        if not slices or not all((100, 0, 0) in sl['minimums'] for sl in slices):
            continue
        identities = {sl['identifier'] for sl in slices if sl['identifier']}
        empty = all(sl['text_size'] == 0 and sl['symbols'] == 0 and sl['kind'] == 6 for sl in slices)
        linked = any(ref in identities or ('/' + framework.name + '/') in ref for ref in references)
        if not empty or linked:
            raise ValueError('高版本框架包含代码或被程序引用，不能直接移除：' + framework.name)
        shutil.rmtree(framework)
        removed.append(framework.name)
    return removed


def validate(app, maximum=(17, 0, 0)):
    app = Path(app)
    checked = 0
    for path, slices in binaries(app):
        for sl in slices:
            if sl['cpu'] != 0x100000c or not sl['platforms'] or set(sl['platforms']) != {2}:
                raise ValueError('不是 arm64 iOS 真机二进制：' + str(path.relative_to(app)))
            if not sl['minimums'] or any(v > maximum for v in sl['minimums']):
                raise ValueError('最低系统版本不兼容：' + str(path.relative_to(app)) + ' ' + str(sl['minimums']))
        checked += 1
    if not checked:
        raise ValueError('应用中没有可执行文件')
    return checked


def normalize_permissions(app):
    app = Path(app)
    app.chmod(0o755)
    for path in app.rglob('*'):
        if path.is_symlink():
            continue
        if path.is_dir():
            path.chmod(0o755)
        else:
            path.chmod(0o755 if inspect_binary(path) else 0o644)
