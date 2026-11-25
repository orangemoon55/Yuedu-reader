#!/usr/bin/env python3
"""Correct one known upstream FFmpegKit plist defect after SPM resolves, before Xcode embeds.
Only the CFBundleIdentifier of libshaderc_combined iOS slices changes. Archive checksums,
framework names, executables, linker identities, other packages and validation stay intact.
"""
from pathlib import Path
import hashlib,json,plistlib,sys

OLD='com.kintan.ksplayer.libshaderc_combined'
NEW='com.kintan.ksplayer.libshaderc-combined'

def normalize(source_packages):
 root=Path(source_packages).resolve()
 xc=root/'checkouts/FFmpegKit/Sources/libshaderc_combined.xcframework'
 if not xc.is_dir():raise RuntimeError('Resolved pinned FFmpegKit framework is missing: '+str(xc))
 manifest=plistlib.loads((xc/'Info.plist').read_bytes()); results=[]
 for library in manifest['AvailableLibraries']:
  if library['SupportedPlatform']!='ios' or library.get('SupportedPlatformVariant') not in (None,'simulator'):continue
  parts=[library['LibraryIdentifier'],library['LibraryPath']]
  if any(Path(x).is_absolute() or '..' in Path(x).parts for x in parts):raise RuntimeError('Unsafe XCFramework path')
  framework=xc/parts[0]/parts[1];p=framework/'Info.plist'
  original=p.read_bytes();info=plistlib.loads(original)
  if info.get('CFBundleIdentifier') not in (OLD,NEW):raise RuntimeError('Unexpected upstream identifier; refuse guessing: '+repr(info.get('CFBundleIdentifier')))
  executable=framework/info['CFBundleExecutable']
  if Path(info['CFBundleExecutable']).name!=info['CFBundleExecutable']:raise RuntimeError('Unsafe executable path')
  before=hashlib.sha256(executable.read_bytes()).hexdigest()
  changed=info['CFBundleIdentifier']==OLD
  if changed:
   backup=root.parent/'readcc-ks-framework-originals'/parts[0]/'Info.plist';backup.parent.mkdir(parents=True,exist_ok=True)
   if backup.exists() and backup.read_bytes()!=original:raise RuntimeError('Existing baseline differs')
   if not backup.exists():backup.write_bytes(original)
   info['CFBundleIdentifier']=NEW
   output=plistlib.dumps(info,fmt=plistlib.FMT_BINARY if original.startswith(b'bplist') else plistlib.FMT_XML,sort_keys=False)
   tmp=p.with_name('Info.plist.readcc-tmp');tmp.write_bytes(output);tmp.replace(p)
  after=plistlib.loads(p.read_bytes())
  assert after==info and after['CFBundleIdentifier']==NEW
  assert hashlib.sha256(executable.read_bytes()).hexdigest()==before
  results.append({'slice':parts[0],'old_identifier':OLD if changed else NEW,'new_identifier':NEW,'changed':changed,'executable_sha256_unchanged':before})
 if not results:raise RuntimeError('No iOS slices in resolved FFmpegKit framework')
 return results

if __name__=='__main__':
 if len(sys.argv)!=2:raise SystemExit('usage: normalize_ksplayer_frameworks.py DerivedData/SourcePackages')
 print(json.dumps({'ks_framework_bundle_id_normalization':normalize(sys.argv[1])},ensure_ascii=False,sort_keys=True))
