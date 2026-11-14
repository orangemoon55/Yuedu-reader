import pathlib
import plistlib
import struct
import tempfile
import unittest

from ipa_compatibility import clean_unused_stubs, inspect_binary, validate


def macho(minimum=17, dependencies=(), text_size=0, symbols=0, kind=6, identifier=None):
    commands = []
    commands.append(struct.pack('<6I', 0x32, 24, 2, minimum << 16, 27 << 16, 0))
    for name, command in [(x, 0xc) for x in dependencies] + ([(identifier, 0xd)] if identifier else []):
        data = name.encode() + b'\0'
        length = (24 + len(data) + 7) // 8 * 8
        commands.append(struct.pack('<6I', command, length, 24, 0, 0, 0) + data + b'\0' * (length - 24 - len(data)))
    commands.append(struct.pack('<6I', 2, 24, 0, symbols, 0, 0))
    section = struct.pack('<16s16sQQ8I', b'__text', b'__TEXT', 0, text_size, 0, 0, 0, 0, 0, 0, 0, 0)
    segment = struct.pack('<II16sQQQQIIII', 0x19, 152, b'__TEXT', 0, 0, 0, 0, 7, 5, 1, 0)
    commands.append(segment + section)
    body = b''.join(commands)
    return struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, kind, len(commands), len(body), 0, 0) + body


class CompatibilityTests(unittest.TestCase):
    def fixture(self, root, linked=False, actual_code=False):
        app = pathlib.Path(root) / 'Test.app'
        framework = app / 'Frameworks/Empty.framework'
        framework.mkdir(parents=True)
        name = '@rpath/Empty.framework/Empty'
        (app / 'Test').write_bytes(macho(dependencies=[name] if linked else [], kind=2, text_size=8))
        (framework / 'Empty').write_bytes(macho(minimum=100, text_size=8 if actual_code else 0, identifier=name))
        (framework / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'Empty'}))
        return app

    def test_remove_only_unreferenced_empty_stub(self):
        with tempfile.TemporaryDirectory() as root:
            app = self.fixture(root)
            with self.assertRaises(ValueError):
                validate(app)
            self.assertEqual(clean_unused_stubs(app), ['Empty.framework'])
            self.assertEqual(validate(app), 1)

    def test_refuse_linked_stub(self):
        with tempfile.TemporaryDirectory() as root:
            app = self.fixture(root, linked=True)
            with self.assertRaises(ValueError):
                clean_unused_stubs(app)
            self.assertTrue((app / 'Frameworks/Empty.framework').exists())

    def test_refuse_real_code_with_high_deployment(self):
        with tempfile.TemporaryDirectory() as root:
            app = self.fixture(root, actual_code=True)
            with self.assertRaises(ValueError):
                clean_unused_stubs(app)

    def test_detect_known_arm64_platform_and_minimum(self):
        with tempfile.TemporaryDirectory() as root:
            path = pathlib.Path(root) / 'binary'
            path.write_bytes(macho(minimum=17, kind=2, text_size=4))
            image = inspect_binary(path)[0]
            self.assertEqual(image['minimums'], [(17, 0, 0)])
            self.assertEqual(image['platforms'], [2])
            self.assertEqual(image['text_size'], 4)


if __name__ == '__main__':
    unittest.main()
