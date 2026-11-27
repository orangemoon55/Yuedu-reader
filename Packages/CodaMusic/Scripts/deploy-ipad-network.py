#!/usr/bin/env python3
"""Install Coda Dev over an explicitly selected Network transport; never launch it.

Requires the locally installed pymobiledevice3 package. No USB fallback or pairing changes.
"""
import argparse
import asyncio
import os
import plistlib
from pathlib import Path
from pymobiledevice3 import usbmux
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.installation_proxy import InstallationProxyService


async def deploy(app: Path, udid: str) -> None:
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    configuration = Path(__file__).resolve().parent.parent / 'Config/AppIdentity.xcconfig'
    identity = next(line.split('=', 1)[1].strip() for line in configuration.read_text().splitlines()
                    if line.startswith('CODA_BUNDLE_IDENTIFIER ='))
    expected = identity + '.dev'
    if info.get('CFBundleIdentifier') != expected:
        raise RuntimeError('Expected a signed Coda Dev app bundle')
    device = await usbmux.select_device(udid, connection_type='Network')
    if device is None:
        raise RuntimeError('iPad Network connection unavailable; USB fallback is disabled')
    print(f'Selected connection: {device.connection_type}; device: {udid}', flush=True)
    async with await create_using_usbmux(serial=udid, connection_type='Network', autopair=False) as lockdown:
        async with InstallationProxyService(lockdown) as installer:
            await installer.install_from_local(app, developer=True)
            installed = (await installer.get_apps(bundle_identifiers=[expected])).get(expected)
            if not installed or installed.get('CFBundleVersion') != info.get('CFBundleVersion'):
                raise RuntimeError('Installed bundle/version could not be verified over Network')
            print(f'Network installation verified: {expected}; version {installed.get("CFBundleVersion")}', flush=True)


def default_udid() -> "str | None":
    if os.environ.get('CODA_IPAD_UDID'):
        return os.environ['CODA_IPAD_UDID']
    env = Path(__file__).resolve().parent.parent / '.env.local'
    if env.exists():
        for line in env.read_text().splitlines():
            key, _, value = line.partition('=')
            if key.strip() == 'CODA_IPAD_UDID' and value.strip():
                return value.strip()
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--device', default=default_udid(),
                        help='iPad UDID; defaults to CODA_IPAD_UDID from the environment or .env.local')
    args = parser.parse_args()
    if not args.device:
        parser.error('set CODA_IPAD_UDID in .env.local or pass --device')
    asyncio.run(asyncio.wait_for(deploy(args.app, args.device), timeout=240))


if __name__ == '__main__':
    main()
