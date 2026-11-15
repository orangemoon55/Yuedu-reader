"""Portable regressions; Apple tool calls are mocked, no cloud or signing required."""
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import prepare_trollstore_test as packaging
from test_ipa_compatibility import macho


class BuildSettingsTests(unittest.TestCase):
    def test_shell_flags_match_both_configuration_guards(self):
        script = (packaging.ROOT / 'scripts/build_trollstore_test.sh').read_text()
        self.assertIn('-configuration Debug', script)
        for key, value in packaging.BUILD_REQUIREMENTS.items():
            if key != 'CONFIGURATION':
                self.assertIn(f'  {key}={value}\n', script)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / 'Products/Test.app'
            actual = dict(packaging.BUILD_REQUIREMENTS, PRODUCT_BUNDLE_IDENTIFIER='com.local.qingyun',
                          WRAPPER_EXTENSION='app', BUILT_PRODUCTS_DIR=str(app.parent), WRAPPER_NAME=app.name)
            settings = root / 'settings.json'
            settings.write_text(json.dumps([{'buildSettings': actual}]))
            path = root / 'app-path.txt'
            with patch.dict(os.environ, TROLLSTORE_PRIVATE_DIR=str(root), TEST_BUNDLE_ID='com.local.qingyun'):
                packaging.locate(settings, path)
            self.assertEqual(path.read_text(), str(app))
            # The same guard is invoked by package() before staging or signing.
            packaging.check_build_settings([actual])
        for key in packaging.BUILD_REQUIREMENTS:
            changed = dict(actual, **{key: 'incorrect'})
            with self.subTest(key=key), self.assertRaises(ValueError):
                packaging.check_build_settings([changed])

    def test_branding_still_verifies_and_detects_tampering(self):
        packaging.verify_brand_icon()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'scripts').mkdir()
            (root / 'scripts/qingyun_branding.json').write_text('{"name":"wrong"}')
            with patch.object(packaging, 'ROOT', root), self.assertRaises(ValueError):
                packaging.verify_brand_icon()

    def test_cloud_guard_still_rejects_non_cloud(self):
        with patch.dict(os.environ, GITHUB_ACTIONS='false'), self.assertRaises(ValueError):
            packaging.cloud_only()


class PackageTests(unittest.TestCase):
    def test_optimized_debug_reaches_archive_and_strips_before_first_signature(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bid = 'com.local.qingyun'
            app = root / 'Products/Test.app'
            settings = root / 'settings.json'
            path_file = root / 'app-path.txt'
            entries = []
            for suffix, relative in [('', ''), ('.shareextension', 'PlugIns/Share.appex'),
                                     ('.widget', 'PlugIns/Widget.appex')]:
                bundle = app / relative
                bundle.mkdir(parents=True)
                packaging.save(bundle / 'Info.plist', {
                    'CFBundleIdentifier': bid + suffix, 'CFBundleExecutable': 'Binary',
                    'CFBundlePackageType': 'XPC!' if suffix else 'APPL',
                    'CFBundleInfoDictionaryVersion': '6.0', 'MinimumOSVersion': '17.0',
                    'ReaderStandalone': True,
                })
                (bundle / 'Binary').write_bytes(macho(kind=2, text_size=16))
                ent = root / packaging.ENTITLEMENTS[suffix]
                ent.parent.mkdir(parents=True, exist_ok=True)
                packaging.save(ent, {'com.apple.security.application-groups': ['group.' + bid]})
                entries.append({'buildSettings': dict(packaging.BUILD_REQUIREMENTS,
                                                      PRODUCT_BUNDLE_IDENTIFIER=bid + suffix)})
            packaging.save(app / 'GoogleService-Info.plist', {'BUNDLE_ID': bid})
            settings.write_text(json.dumps(entries))
            path_file.write_text(str(app))
            calls = []

            def apple_tool(*args):
                calls.append(args)
                if args[0] == '/usr/bin/ditto':
                    shutil.copytree(args[-2], args[-1], symlinks=True)
                return ''

            output = root / 'Qingyun-v8.ipa'
            with patch.dict(os.environ, TROLLSTORE_PRIVATE_DIR=str(root), TEST_BUNDLE_ID=bid), \
                    patch.object(packaging, 'ROOT', root), \
                    patch.object(packaging, 'cloud_only'), \
                    patch.object(packaging, 'check_binary'), \
                    patch.object(packaging, 'run', side_effect=apple_tool), \
                    contextlib.redirect_stdout(io.StringIO()):
                packaging.package(settings, path_file, output)
            strips = [i for i, call in enumerate(calls) if call[:3] == ('xcrun', 'strip', '-S')]
            signatures = [i for i, call in enumerate(calls) if call[:2] == ('/usr/bin/codesign', '--force')]
            self.assertEqual(len(strips), 3)
            self.assertEqual(len(signatures), 3)
            self.assertLess(max(strips), min(signatures))
            with zipfile.ZipFile(output) as archive:
                self.assertIsNone(archive.testzip())
                self.assertIn('Payload/Test.app/Info.plist', archive.namelist())


class StripTests(unittest.TestCase):
    def test_all_real_linked_images_stripped_once_before_signing(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'Test.app'
            app.mkdir()
            images = []
            for name, kind in [('Test', 2), ('Frameworks/A.framework/A', 6),
                               ('PlugIns/Share.appex/Share', 2), ('Code.bundle/Code', 8)]:
                path = app / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(macho(kind=kind, text_size=32) + b'debug padding')
                images.append(path)
            (app / 'Alias').symlink_to('Test')
            resource = app / 'real.js'
            resource.write_bytes(b'real business resource')
            calls = []

            def strip(*args):
                self.assertEqual(args[:3], ('xcrun', 'strip', '-S'))
                path = args[3]
                calls.append(path)
                path.write_bytes(path.read_bytes().removesuffix(b'debug padding'))
                return ''

            with patch.object(packaging, 'run', side_effect=strip):
                before, after = packaging.strip_debug_symbols(app)
            self.assertCountEqual(calls, images)
            self.assertEqual(before - after, len(images) * len(b'debug padding'))
            self.assertEqual(resource.read_bytes(), b'real business resource')

    def test_unknown_macho_type_fails_before_any_strip(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            (app / 'Binary').write_bytes(macho(kind=1))
            with patch.object(packaging, 'run') as run, self.assertRaises(ValueError):
                packaging.strip_debug_symbols(app)
            run.assert_not_called()


class ArchiveTests(unittest.TestCase):
    def fixture(self, root):
        payload = root / 'Payload'
        app = payload / '轻云出岫.app'
        app.mkdir(parents=True)
        (app / 'Test').write_bytes(b'code' * 4096)
        (app / 'Test').chmod(0o755)
        (app / 'Info.plist').write_bytes(b'<plist/>')
        (app / 'Info.plist').chmod(0o644)
        resources = app / 'Versions/A/Resources'
        resources.mkdir(parents=True)
        (resources / 'zh-Hans.js').write_bytes('业务资源'.encode() * 500)
        (app / 'Versions/Current').symlink_to('A', target_is_directory=True)
        (app / 'Resources').symlink_to('Versions/Current/Resources', target_is_directory=True)
        return payload, app

    def test_exact_tree_permissions_symlinks_level9_and_crc(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload, app = self.fixture(root)
            output = root / 'Qingyun-v8.ipa'
            with patch.object(zipfile.ZipFile, 'write', autospec=True,
                              side_effect=zipfile.ZipFile.write) as write:
                before, after = packaging.write_ipa(payload, output)
                self.assertTrue(write.called)
                self.assertTrue(all(call.args[0].compresslevel == 9 for call in write.call_args_list))
            self.assertLess(after, before)
            with zipfile.ZipFile(output) as archive:
                self.assertIsNone(archive.testzip())
                prefix = f'Payload/{app.name}/'
                executable = archive.getinfo(prefix + 'Test')
                self.assertEqual(stat.S_IMODE(executable.external_attr >> 16), 0o755)
                for item in archive.infolist():
                    self.assertTrue(item.filename == 'Payload/' or item.filename.startswith(prefix))
                    self.assertEqual(item.compress_type, zipfile.ZIP_DEFLATED)
                for name, target in [('Resources', 'Versions/Current/Resources'), ('Versions/Current', 'A')]:
                    link = archive.getinfo(prefix + name)
                    self.assertTrue(stat.S_ISLNK(link.external_attr >> 16))
                    self.assertEqual(archive.read(link), target.encode())
                # Symlink directories must not be traversed or duplicated.
                self.assertNotIn(prefix + 'Resources/zh-Hans.js', archive.namelist())
                resource = prefix + 'Versions/A/Resources/zh-Hans.js'
                self.assertEqual(archive.read(resource), (app / 'Versions/A/Resources/zh-Hans.js').read_bytes())

    def test_reject_unsafe_links_or_metadata_before_creating_ipa(self):
        for target in ['/etc/passwd', '../../../outside', 'missing', 'Link']:
            with self.subTest(target=target), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                payload, app = self.fixture(root)
                (app / 'Link').symlink_to(target)
                output = root / 'Test.ipa'
                with self.assertRaises(ValueError):
                    packaging.write_ipa(payload, output)
                self.assertFalse(output.exists())
        for name in ['._Info.plist', '__MACOSX/junk']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                payload, app = self.fixture(root)
                path = app / name
                path.parent.mkdir(exist_ok=True)
                path.write_bytes(b'metadata')
                with self.assertRaises(ValueError):
                    packaging.write_ipa(payload, root / 'Test.ipa')


if __name__ == '__main__':
    unittest.main()
