#!/usr/bin/env python3
"""One-time candidate-only project wiring; never touches upstream/parent."""
from pathlib import Path
import shutil, re
root=Path(__file__).resolve().parents[1]
pkg=root/'Packages/CodaMusic'
if 'C0DA00000000000000000001' in (root/'Yuedu-Reader.xcodeproj/project.pbxproj').read_text():
    raise SystemExit('CodaCore is already wired. Do not rerun preparation; use verify_coda_integration.py instead.')
manifest='''// swift-tools-version: 6.1
import PackageDescription

// Readcc iOS integration of Coda v0.1.2. Original manifest is preserved in
// Package.upstream.swift.txt. macOS launcher/ObjC/Sparkle sources stay intact,
// but do not participate in this iOS-only dependency graph.
let package = Package(
    name: "CodaMusic",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("16.0")],
    products: [.library(name: "CodaCore", targets: ["CodaCore"])],
    dependencies: [],
    targets: [
        .target(
            name: "CodaCore",
            path: "Sources/Coda",
            resources: [
                .process("Resources"),
                .copy("Features/Home/QishuiModeIcons"),
                .copy("Core/API/QishuiVerificationAssets"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CodaCoreTests",
            dependencies: ["CodaCore"],
            path: "Tests/CodaCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
'''
(pkg/'Package.swift').write_text(manifest)
legal=pkg/'Sources/Coda/Resources/CodaLegal'
legal.mkdir(exist_ok=True)
for f in ['LICENSE','COPYING']:
    shutil.copy2(pkg/f,legal/f)
shutil.copytree(pkg/'ThirdPartyNotices',legal/'ThirdPartyNotices',dirs_exist_ok=True)
# Keep nested legal document names rather than flattening them via .process.
s=(pkg/'Package.swift').read_text().replace('.process("Resources"),','.process("Resources/en.lproj"),\n                .process("Resources/zh-Hans.lproj"),\n                .copy("Resources/PrivacyInfo.xcprivacy"),\n                .copy("Resources/CodaLegal"),')
(pkg/'Package.swift').write_text(s)
p=root/'Yuedu-Reader.xcodeproj/project.pbxproj'
s=p.read_text()
def once(old,new):
    global s
    if s.count(old)!=1: raise RuntimeError(f'Expected unique anchor: {old[:80]}')
    s=s.replace(old,new,1)
if 'C0DA00000000000000000001' not in s:
    once('/* End PBXBuildFile section */','\t\tC0DA00000000000000000002 /* CodaCore in Frameworks */ = {isa = PBXBuildFile; productRef = C0DA00000000000000000003 /* CodaCore */; };\n\t\tC0DA00000000000000000004 /* CodaCore in Frameworks */ = {isa = PBXBuildFile; productRef = C0DA00000000000000000005 /* CodaCore */; };\n/* End PBXBuildFile section */')
    once('\t\t460D36562F51C5B8006E774C /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (','\t\t460D36562F51C5B8006E774C /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\tC0DA00000000000000000002 /* CodaCore in Frameworks */,')
    once('\t\t460D36632F51C5B9006E774C /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (','\t\t460D36632F51C5B9006E774C /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\tC0DA00000000000000000004 /* CodaCore in Frameworks */,')
    once('\t\t\tname = "yuedu app";\n\t\t\tpackageProductDependencies = (','\t\t\tname = "yuedu app";\n\t\t\tpackageProductDependencies = (\n\t\t\t\tC0DA00000000000000000003 /* CodaCore */,')
    once('\t\t\tname = "yuedu appTests";','\t\t\tname = "yuedu appTests";\n\t\t\tpackageProductDependencies = (\n\t\t\t\tC0DA00000000000000000005 /* CodaCore */,\n\t\t\t);')
    once('\t\t\tpackageReferences = (','\t\t\tpackageReferences = (\n\t\t\t\tC0DA00000000000000000001 /* XCLocalSwiftPackageReference "Packages/CodaMusic" */,')
    once('/* End XCLocalSwiftPackageReference section */','\t\tC0DA00000000000000000001 /* XCLocalSwiftPackageReference "Packages/CodaMusic" */ = {\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = Packages/CodaMusic;\n\t\t};\n/* End XCLocalSwiftPackageReference section */')
    once('/* End XCSwiftPackageProductDependency section */','\t\tC0DA00000000000000000003 /* CodaCore */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = C0DA00000000000000000001;\n\t\t\tproductName = CodaCore;\n\t\t};\n\t\tC0DA00000000000000000005 /* CodaCore */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = C0DA00000000000000000001;\n\t\t\tproductName = CodaCore;\n\t\t};\n/* End XCSwiftPackageProductDependency section */')
    p.write_text(s)
print('Wired local CodaCore into app + unit tests; copied module legal resources; no host signing changes.')
