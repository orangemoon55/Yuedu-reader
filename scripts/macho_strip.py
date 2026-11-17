"""Portable strip guard: hash runtime data, never edit Mach-O files.

Darwin strip -S -x removes debug/local nlist entries, keeping global symbols.
Offsets in __LINKEDIT may move; compare payloads rather than their file offsets.
"""
import hashlib
import mmap
from pathlib import Path
import struct


def snapshot(path):
    with Path(path).open('rb') as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        def unpack(fmt, offset):
            return struct.unpack_from(fmt, data, offset)

        def digest(offset, size):
            if offset < 0 or size < 0 or offset + size > len(data):
                raise ValueError('Mach-O 数据区越界：' + Path(path).name)
            value = hashlib.sha256()
            for start in range(offset, offset + size, 1024 * 1024):
                value.update(data[start:min(start + 1024 * 1024, offset + size)])
            return size, value.hexdigest()

        magic = data[:4]
        if magic in (b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'):
            endian = '>' if magic[0] == 0xca else '<'
            count = unpack(endian + 'I', 4)[0]
            if not 0 < count <= 32:
                raise ValueError('Mach-O 架构数量无效')
            wide = magic in (b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')
            fmt = endian + ('IIQQII' if wide else 'IIIII')
            offsets = [unpack(fmt, 8 + n * struct.calcsize(fmt))[2] for n in range(count)]
        else:
            offsets = [0]
        result = []
        for base in offsets:
            magic = data[base:base + 4]
            if magic not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
                raise ValueError('只支持已验证的 64 位 Mach-O')
            endian = '<' if magic[0] == 0xcf else '>'
            header = unpack(endian + '8I', base)
            count, command_bytes = header[4:6]
            if count > 8192 or command_bytes > 8 * 1024 * 1024:
                raise ValueError('Mach-O 指令区过大')
            cursor, end = base + 32, base + 32 + command_bytes
            sections, loader, symbols = [], [], None
            for _ in range(count):
                cmd, size = unpack(endian + 'II', cursor)
                if size < 8 or cursor + size > end or end > len(data):
                    raise ValueError('Mach-O 指令区损坏')
                if cmd == 0x19:  # LC_SEGMENT_64; retain Swift/ObjC/unwind/code data.
                    segment = unpack(endian + 'II16sQQQQIIII', cursor)
                    for n in range(segment[-2]):
                        section = unpack(endian + '16s16sQQ8I', cursor + 72 + n * 80)
                        name, segname, address, length, offset, align, reloff, nreloc, flags, r1, r2, r3 = section
                        if segname.rstrip(b'\0') != b'__DWARF':
                            zerofill = flags & 0xff in {1, 0xc, 0x12}
                            sections.append((name, segname, address, length, align, flags, r1, r2, r3,
                                             None if zerofill else digest(base + offset, length)))
                elif cmd in {0x22, 0x80000022}:  # LC_DYLD_INFO[_ONLY]
                    values = unpack(endian + '12I', cursor)[2:]
                    loader.append((cmd, tuple(digest(base + values[n], values[n + 1])
                                              for n in range(0, 10, 2))))
                elif cmd in {0x80000033, 0x80000034}:  # exports trie / chained fixups
                    offset, length = unpack(endian + 'II', cursor + 8)
                    loader.append((cmd, digest(base + offset, length)))
                elif cmd == 0x1b:  # LC_UUID stays useful for matching the separate dSYM.
                    loader.append((cmd, data[cursor + 8:cursor + size]))
                elif cmd == 2:
                    symbols = unpack(endian + '6I', cursor)[2:]
                cursor += size
            if cursor != end:
                raise ValueError('Mach-O 指令长度不一致')
            local = debug = 0
            globals_ = []
            if symbols:
                symoff, nsyms, stroff, strsize = symbols
                if base + symoff + nsyms * 16 > len(data) or base + stroff + strsize > len(data):
                    raise ValueError('Mach-O 符号表越界')

                def symbol_name(index):
                    if index >= strsize:
                        raise ValueError('Mach-O 全局符号字符串越界')
                    start = base + stroff + index
                    stop = data.find(b'\0', start, base + stroff + strsize)
                    if stop < 0:
                        raise ValueError('Mach-O 全局符号字符串未终止')
                    name = data[start:stop]
                    return struct.pack('<I', len(name)) + name

                for n in range(nsyms):
                    record = base + symoff + n * 16
                    index, kind, section, desc, value = unpack(endian + 'IBBHQ', record)
                    if kind & 0xe0:  # N_STAB
                        debug += 1
                    elif kind & 1:  # N_EXT (defined and undefined, including weak symbols)
                        # N_INDR n_value is another string index, not a runtime address.
                        target = symbol_name(value) if kind & 0xe == 0xa else struct.pack('<Q', value)
                        globals_.append(struct.pack('<BBH', kind, section, desc) + target + symbol_name(index))
                    else:
                        local += 1
            exports = hashlib.sha256()
            for entry in sorted(globals_):
                exports.update(entry)
            result.append({'runtime': (header[1:4], header[6:], sections, loader,
                                       len(globals_), exports.hexdigest()),
                           'local': local, 'debug': debug, 'global': len(globals_)})
        return result
