"""Portable Mach-O fixtures; no native strip or signing tools are invoked."""
import contextlib
import io
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from macho_strip import snapshot
import prepare_trollstore_test as packaging


def image(local=True, debug=True, global_name=b'_public', code=b'CODE', metadata=b'META', exports=b'EXPORT', sentinel=False):
    strings = bytearray(b'\0')
    symbols = []
    for name, kind, section, value in [(b'radr://5614542', 0x3c, 0, 0x05614542)] * sentinel + \
            [(b'_local', 0xe, 1, 0x1000)] * local + \
            [(b'debug', 0x24, 1, 0x1000)] * debug + \
            [(global_name, 0xf, 1, 0x1000), (b'_import', 1, 0, 0)]:
        symbols.append(struct.pack('<IBBHQ', len(strings), kind, section, 0, value))
        strings.extend(name + b'\0')
    commands_size = 24 + 24 + 24 + 16 + 72 + 2 * 80
    offset = 32 + commands_size
    section = lambda name, size, where: struct.pack('<16s16sQQ8I', name, b'__TEXT',
                                                  0x1000 + where - offset, size, where, 2, 0, 0, 0, 0, 0, 0)
    segment = struct.pack('<II16sQQQQIIII', 0x19, 232, b'__TEXT', 0x1000, 4096,
                          0, offset + len(code) + len(metadata), 7, 5, 2, 0)
    body = code + metadata + exports
    symoff = offset + len(body)
    commands = b''.join([
        struct.pack('<6I', 0x32, 24, 2, 17 << 16, 27 << 16, 0),
        struct.pack('<6I', 2, 24, symoff, len(symbols), symoff + len(symbols) * 16, len(strings)),
        struct.pack('<II16s', 0x1b, 24, b'unchanged-uuid!!!'),
        struct.pack('<4I', 0x80000033, 16, offset + len(code) + len(metadata), len(exports)),
        segment + section(b'__text', len(code), offset) +
        section(b'__swift5_fieldmd', len(metadata), offset + len(code)),
    ])
    return struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 5, len(commands), 0, 0) + \
        commands + body + b''.join(symbols) + strings


class StripGuardTests(unittest.TestCase):
    def apply(self, before, after):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'Binary'
            path.write_bytes(before)
            original = snapshot(path)

            def strip(*args):
                self.assertEqual(args, ('xcrun', 'strip', '-S', '-x', path))
                path.write_bytes(after)
                return ''

            with patch.object(packaging, 'run', side_effect=strip), contextlib.redirect_stdout(io.StringIO()):
                sizes = packaging.strip_debug_symbols(path.parent)
            return original, snapshot(path), sizes

    def test_remove_debug_local_preserves_globals_and_runtime(self):
        before, after, sizes = self.apply(image(), image(local=False, debug=False))
        self.assertEqual((before[0]['local'], before[0]['debug'], before[0]['global']), (1, 1, 2))
        self.assertEqual((after[0]['local'], after[0]['debug'], after[0]['global']), (0, 0, 2))
        self.assertEqual(before[0]['runtime'], after[0]['runtime'])
        self.assertGreater(sizes[0], sizes[1])

    def test_indirect_global_alias_survives_string_repacking(self):
        def alias(data):
            data = bytearray(data)
            symoff, count = struct.unpack_from('<II', data, 32 + 24 + 8)
            target = struct.unpack_from('<I', data, symoff + (count - 1) * 16)[0]
            record = symoff + (count - 2) * 16
            struct.pack_into('<BBHQ', data, record + 4, 0xb, 0, 0, target)
            return data

        before, after, _ = self.apply(alias(image()), alias(image(local=False, debug=False)))
        self.assertEqual(before[0]['runtime'], after[0]['runtime'])

    def test_apple_dyld_compatibility_sentinel_is_allowed(self):
        before, after, _ = self.apply(image(), image(local=False, debug=False, sentinel=True))
        self.assertEqual(after[0]['sentinel'], 1)
        self.assertEqual((after[0]['local'], after[0]['debug']), (0, 0))
        self.assertEqual(before[0]['runtime'], after[0]['runtime'])

    def test_fake_sentinel_is_not_accepted(self):
        data = bytearray(image(local=False, debug=False, sentinel=True))
        symoff = struct.unpack_from('<I', data, 32 + 24 + 8)[0]
        struct.pack_into('<Q', data, symoff + 8, 0)
        with self.assertRaisesRegex(ValueError, '本地或调试符号'):
            self.apply(image(), data)

    def test_reject_noop_strip_with_local_symbols(self):
        with self.assertRaisesRegex(ValueError, '本地或调试符号'):
            self.apply(image(), image())

    def test_reject_lost_export_or_changed_runtime_bytes(self):
        for changes in [{'global_name': b'_private'}, {'code': b'FAIL'},
                        {'metadata': b'FAIL'}, {'exports': b'BROKEN'}]:
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, 'strip 改变'):
                self.apply(image(), image(local=False, debug=False, **changes))

    def test_fat_slice_is_checked(self):
        thin = image(local=False, debug=False)
        fat = struct.pack('>7I', 0xcafebabe, 1, 0x100000c, 0, 4096, len(thin), 12)
        fat += b'\0' * (4096 - len(fat)) + thin
        before, after, _ = self.apply(fat, fat)
        self.assertEqual(before, after)

    def test_malformed_symbol_string_fails_closed(self):
        data = bytearray(image(local=False, debug=False))
        # LC_SYMTAB follows LC_BUILD_VERSION; deliberately invalid first n_strx.
        symoff = struct.unpack_from('<I', data, 32 + 24 + 8)[0]
        struct.pack_into('<I', data, symoff, 0xffffffff)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'Binary'
            path.write_bytes(data)
            with self.assertRaisesRegex(ValueError, '字符串越界'):
                snapshot(path)


if __name__ == '__main__':
    unittest.main()
