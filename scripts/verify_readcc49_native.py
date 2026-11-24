#!/usr/bin/env python3
"""Compile the actual importer at both commits; exercise fetch/commit via loopback.
No remote source scripts, login state or user cookies are used or executed.
"""
import base64, hashlib, http.server, json, os, pathlib, shutil, subprocess, tempfile, threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'trollstore-output'
OUT.mkdir(exist_ok=True)
BASE = '96e9b4bd0056f49cc01e960e28fc82b88f59e378'
MOD = '78a7e23fad59e9244752355ea543dc451831a68b'
FILES = ['Modules/Services/Md5Sources/Md5Source.swift',
         'Modules/Services/Md5Sources/Md5SourceImportModel.swift']
FIXTURE = b'// local fixture only; never execute this file\n'
AUTH = 'Basic ' + base64.b64encode(b'fixture:fixture').decode()
CALLS = []

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        authenticated = self.headers.get('Authorization') == AUTH
        code = 200 if authenticated and self.path in ('/cat/index.js', '/cat/index.js.md5') else 404
        CALLS.append({'path': self.path, 'authCorrect': authenticated, 'status': code})
        self.send_response(code)
        self.end_headers()
        if code == 200:
            self.wfile.write(hashlib.md5(FIXTURE).hexdigest().encode() if self.path.endswith('.md5') else FIXTURE)

DRIVER = r'''
import Foundation
func localized(_ key: String) -> String { key }
@main struct ImportContract {
    @MainActor static func main() async throws {
        let address = CommandLine.arguments[1]
        let expectedSuccess = CommandLine.arguments[2] == "success"
        let root = URL(fileURLWithPath: CommandLine.arguments[3])
        let library = Md5SourceLibrary(store: Md5SourceStore(directory: root))
        let model = Md5SourceImportModel(library: library)
        model.address = address
        let targets = Md5SourceImportModel.targets(for: address)!
        print("bundlePath=\(targets.bundle.path)")
        await model.fetch()
        switch model.phase {
        case .preview(let preview):
            precondition(expectedSuccess, "baseline unexpectedly succeeded")
            precondition(preview.checksum == Md5SourceImportModel.md5(of: preview.data))
            precondition(targets.bundle.lastPathComponent == "index.js")
            await model.commit()
            guard case .done(let installed) = model.phase else { fatalError("not installed") }
            precondition(library.sources.count == 1)
            let stored = try Data(contentsOf: library.bundleURL(for: installed))
            precondition(stored == preview.data)
            print("preview=checksum_verified installed=1")
        case .failed(let message):
            precondition(!expectedSuccess, "modified failed: \(message)")
            precondition(message.contains("HTTP 404"), "unexpected failure: \(message)")
            print("fetch=HTTP404 installed=0")
        default: fatalError("unexpected phase")
        }
    }
}
'''

def show(ref, file):
    return subprocess.check_output(['git', 'show', f'{ref}:{file}'], cwd=ROOT)

def main():
    assert shutil.which('swiftc'), 'This check needs the macOS Swift toolchain.'
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    address = f'http://fixture:fixture@127.0.0.1:{server.server_port}/cat/index.js.md5'
    baseline = {f: show(BASE, f) for f in FILES}
    modified = {f: show(MOD, f) for f in FILES}
    original_hash = hashlib.sha256(baseline[FILES[1]]).hexdigest()
    evidence = {'base': BASE, 'modified': MOD, 'baselineHash': original_hash, 'runs': []}
    with tempfile.TemporaryDirectory(prefix='readcc49-native-') as temporary:
        temp = pathlib.Path(temporary)
        for label, originals, expect in [('BASELINE', baseline, 'failure'), ('MODIFIED', modified, 'success'),
                                          ('ROLLBACK', baseline, 'failure')]:
            stage = temp / label
            stage.mkdir()
            for file, contents in originals.items():
                (stage / pathlib.Path(file).name).write_bytes(contents)
            (stage / 'Driver.swift').write_text(DRIVER)
            binary = stage / 'contract'
            command = ['swiftc', '-swift-version', '6', '-parse-as-library',
                       str(stage/'Md5Source.swift'), str(stage/'Md5SourceImportModel.swift'),
                       str(stage/'Driver.swift'), '-o', str(binary)]
            compile_result = subprocess.run(command, text=True, capture_output=True)
            evidence['runs'].append({'role': label, 'compileExit': compile_result.returncode,
                                     'compileStdout': compile_result.stdout, 'compileStderr': compile_result.stderr})
            print(label, 'compileExit=', compile_result.returncode, flush=True)
            if compile_result.returncode:
                print(compile_result.stderr, flush=True)
                raise RuntimeError('Swift compile failed')
            run = subprocess.run([str(binary), address, expect, str(stage/'state')], text=True, capture_output=True, timeout=30)
            evidence['runs'][-1].update({'exit': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr})
            print(label, 'exit=', run.returncode, '\n'+run.stdout, run.stderr, flush=True)
            assert run.returncode == 0
            if label == 'ROLLBACK':
                assert hashlib.sha256((stage/'Md5SourceImportModel.swift').read_bytes()).hexdigest() == original_hash
        profile = 'Modules/Features/Settings/ProfileView.swift'
        manager = 'Modules/Features/Library/Modules/RuleModuleManagerView.swift'
        for ref, label, count in [(BASE, 'BASELINE', 2), (MOD, 'MODIFIED', 1), (BASE, 'ROLLBACK', 2)]:
            observed = show(ref, profile).count(b'accessibilityIdentifier("settings_md5_sources")')
            observed += show(ref, manager).count(b'accessibilityIdentifier("modules.md5Sources")')
            print(label, 'navigationEntrySourceCount=', observed, flush=True)
            assert observed == count
        evidence['calls'] = CALLS
        print('loopback=', json.dumps(CALLS, ensure_ascii=False), flush=True)
        print('PASS native Swift importer and source-entry contract; not an iOS UI/device test', flush=True)
    server.shutdown()
    (OUT/'readcc49-native.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
