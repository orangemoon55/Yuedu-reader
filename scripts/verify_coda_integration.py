#!/usr/bin/env python3
"""Offline production linkage/resources assertions, NOT an Xcode build."""
from pathlib import Path
import hashlib,json,plistlib,subprocess
R=Path(__file__).resolve().parents[1];V=R/'Packages/CodaMusic';C=V/'Sources/Coda'
checks=[]
def check(name,value):
 checks.append({'name':name,'pass':bool(value)})
 assert value,name
project=R/'Yuedu-Reader.xcodeproj'
ruby="require 'xcodeproj';require 'json';p=Xcodeproj::Project.open(ARGV[0]);puts JSON.generate(p.targets.map{|t|{name:t.name,products:t.package_product_dependencies.map(&:product_name),frameworks:t.frameworks_build_phase.files.map{|f|f.product_ref&.product_name}.compact}})"
p=subprocess.run(['ruby','-e',ruby,str(project)],capture_output=True,text=True)
check('Native pbxproj parser exit0',p.returncode==0)
targets=json.loads(p.stdout)
for name in ['yuedu app','yuedu appTests']:
 t=next(t for t in targets if t['name']==name)
 check(name+' links CodaCore product and Frameworks', 'CodaCore' in t['products'] and 'CodaCore' in t['frameworks'])
manifest=(V/'Package.swift').read_text()
check('Swift5 isolated local module, no new network dependency', '.swiftLanguageMode(.v5)' in manifest and 'dependencies: []' in manifest)
check('329 original core files retained',len(list(C.rglob('*.swift')))>=329)
for path in ['Resources/en.lproj','Resources/zh-Hans.lproj','Resources/PrivacyInfo.xcprivacy','Resources/CodaLegal','Features/Home/QishuiModeIcons','Core/API/QishuiVerificationAssets']:
 check('Module resource exists '+path,(C/path).exists() and '"'+path+'"' in manifest)
for name in ['LICENSE','COPYING','ThirdPartyNotices/README.md']:
 check('Module legal exact '+name,(V/name).read_bytes()==(C/'Resources/CodaLegal'/name).read_bytes())
check('Legal resolver uses module not host root','Bundle.module.resourceURL' in (C/'Core/AppAboutInfo.swift').read_text())
icons=list((C/'Features/Home/QishuiModeIcons').glob('*.png'))
check('48 usable original replacement mode PNGs',len(icons)==48 and all(p.read_bytes().startswith(b'\x89PNG\r\n\x1a\n') and p.with_suffix('.svg').is_file() for p in icons))
assets=V/'ios/CodaIOS/Assets.xcassets'
for images in sorted(assets.glob('*.imageset')):
 for source in images.rglob('*'):
  if source.is_file():check('iOS image byte-exact '+str(source.relative_to(assets)),source.read_bytes()==(R/'Resources/CodaMusicAssets.xcassets'/source.relative_to(assets)).read_bytes())
info=plistlib.loads((R/'Info.plist').read_bytes())
check('Original Readcc background audio retained','audio' in info['UIBackgroundModes'])
check('No false CarPlay entitlement claim', 'UIApplicationSceneManifest' not in info or 'CPTemplateApplicationSceneSessionRoleApplication' not in str(info['UIApplicationSceneManifest']))
check('Real Coda destination and legacy escape hatch','IOSMainWindow(initialDestination:' in (R/'Modules/Features/Music/CodaMusicDestination.swift').read_text())
print(json.dumps({'pass':True,'meaning':'Offline source/project/resource checks only, native compilation/runtime unverified','checks':checks,'pbxproj_parser_stdout':p.stdout,'pbxproj_parser_stderr':p.stderr,'pbxproj_parser_exit':p.returncode},ensure_ascii=False,indent=2))
