#!/usr/bin/env python3
"""Executable source/schema evidence only; NOT Swift compilation or native parser execution."""
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
FILES = [
    'Modules/Features/Library/Modules/RuleModuleManagerView.swift',
    'Modules/Features/Library/Modules/ModuleMediaManagerView.swift',
    'Modules/Features/Settings/Md5SourceManagerView.swift',
    'Modules/Features/Settings/Md5CloudAccountsView.swift',
    'Modules/Services/RuleModules/ModuleMediaImportModels.swift',
    'Modules/Services/RuleModules/ModuleMediaImportStore.swift',
    'Tests/iOS/yuedu appTests/ModuleMediaImportTests.swift',
]
checks = []
def check(name, value):
    assert value, name
    checks.append(name)

text = {Path(f).name: (ROOT / f).read_text() for f in FILES}
models = text['ModuleMediaImportModels.swift']
store = text['ModuleMediaImportStore.swift']
landing = text['RuleModuleManagerView.swift']
ui = text['ModuleMediaManagerView.swift']
cat = text['Md5SourceManagerView.swift']
check('real module destinations retained', all(x in landing for x in [
    'ExploreNavigationRoute.moduleGroup(.official)', 'ExploreNavigationRoute.moduleGroup(.imported)',
    'ExploreNavigationRoute.moduleRepository(repository.id)', 'RuleModuleAddMenuItems(flow: addFlow)']))
check('three media routes have concrete destinations', all(x in landing for x in [
    'case .danmaku: ModuleMediaManagerView(kind: .danmaku)',
    'case .subtitles: ModuleMediaManagerView(kind: .subtitle)',
    'case .catSources: Md5SourceManagerView(library: md5Library)']))
check('counts use actual library entries including unreadable imported folders', all(x in models + landing for x in [
    'official = appOfficial + installedOfficial', 'imported = installedImported + unreadableImported',
    'library.official.count', 'library.imported.count', 'library.failures.count', 'md5Library.sources.count']))
check('all file and clipboard actions call the real store', all(x in ui for x in [
    '.fileImporter(', 'readBounded(url,', 'store.importSubtitle(data, filename: filename)',
    'store.importRegistry(data, kind: kind)', 'UIPasteboard.general.string', 'ModuleSubtitlePreviewView(file: file)']))
check('bounded inputs and GBK decoder declared', all(x in models for x in [
    '256 * 1024', '4 * 1024 * 1024', '20_000', '16_384', 'GB_18030_2000', 'String(data: data, encoding: .utf8)']))
check('archive is atomic and publishes only after disk write', store.index('try data.write(to: archiveURL, options: .atomic)') < store.index('archive = next'))
check('corrupt archive blocks writes and remains untouched', 'guard loadFailure == nil' in store and 'removeItem' not in store)
check('registry does not call remote or script engines', not re.search(r'URLSession|dataTask|CatVodRuntime|evaluateScript|MusicJS', models + store))
check('matching limitation is explicit in landing and manager', '播放匹配尚未接入' in landing and '自動匹配、下載與字幕掛載尚未接入' in ui)
check('no unsupported Python UI advertised', 'Python' not in landing + ui + cat)
check('cat account link reaches existing actual credential view', all(x in cat for x in ['Md5CloudAccountsView(library: library)', 'PanCookieSettingsView(source: source, sites: sites)']))
check('account picker requires explicit activation', '.activate(' not in text['Md5CloudAccountsView.swift'] and 'opensAccounts: true' in text['Md5CloudAccountsView.swift'])
check('native parser/store tests are included', text['ModuleMediaImportTests.swift'].count('@Test(') == 11)

# A deliberately independent schema fixture oracle, not a translation/runtime of Swift.
def registry_fixture(raw, kind):
    data = raw.encode('utf-8')
    if not 0 < len(data) <= 256 * 1024:
        raise ValueError('byte limit')
    value = json.loads(raw.lstrip('\ufeff').strip())
    if kind == 'subtitle' and isinstance(value, dict):
        value = [value]
    if not isinstance(value, list) or not 0 < len(value) <= 100:
        raise ValueError('array/count')
    ids = set()
    for item in value:
        for field, maximum in [('id', 128), ('name', 128), ('baseUrl', 2048)]:
            v = item.get(field)
            if not isinstance(v, str) or not v.strip() or len(v) > maximum or any(ord(c) < 32 or ord(c) == 127 for c in v):
                raise ValueError('field')
        u = urlsplit(item['baseUrl'])
        if u.scheme not in ('http', 'https') or not u.hostname or u.username or u.password or u.fragment:
            raise ValueError('url')
        if item['id'] in ids:
            raise ValueError('duplicate')
        ids.add(item['id'])
    return value

valid = {'id': 'fixture', 'name': 'Fixture', 'baseUrl': 'https://example.invalid/api'}
check('schema fixture: Dandanplay array', len(registry_fixture(json.dumps([valid]), 'danmaku')) == 1)
check('schema fixture: SubtitleDB explicit object', len(registry_fixture(json.dumps(valid), 'subtitle')) == 1)
for name, obj in [('danmaku-object', valid), ('empty', []), ('duplicate-id', [valid, valid]),
                  ('missing-fields', [{'id': 'x'}]), ('too-many', [dict(valid, id=str(i)) for i in range(101)]),
                  ('userinfo', [dict(valid, baseUrl='https://user:pass@example.invalid/api')]),
                  ('non-http', [dict(valid, baseUrl='file:///tmp/a')])]:
    try:
        registry_fixture(json.dumps(obj), 'danmaku')
    except ValueError:
        checks.append('schema rejection fixture: ' + name)
    else:
        raise AssertionError(name)

# Syntax parse only. This cannot prove typechecking, linking, Apple framework behavior or UI fit.
import tree_sitter
import tree_sitter_swift
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
syntax = []
for filename in FILES:
    data = (ROOT / filename).read_bytes()
    tree = parser.parse(data)
    errors = []
    def visit(node):
        if node.type == 'ERROR' or node.is_missing:
            errors.append({'type': node.type, 'row': node.start_point.row + 1, 'column': node.start_point.column + 1})
        for child in node.children:
            visit(child)
    visit(tree.root_node)
    check('Swift syntax: ' + filename, not errors)
    syntax.append({'file': filename, 'errors': errors})

print(json.dumps({'status': 'PASS', 'checks': len(checks), 'check_names': checks,
                  'swift_syntax': syntax, 'native_tests_added': 11,
                  'native_tests_executed': False,
                  'limitations': ['No Swift compiler/Xcode present', 'Source contracts and Python schema fixtures are NOT native parser execution', 'No simulator/device UI rendering or playback verified']},
                 ensure_ascii=False, indent=2))
