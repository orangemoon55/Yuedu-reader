# qishui-api protocol reference

Source: https://github.com/guowenye/qishui-api

Reference commit: e409c10fe7441a10d370da7da61d62bbc1e5126c

Kumone's native `QishuiMusicAPI.swift` adapts endpoint parameters, QR cookie handling and resource normalization from this reference. It does not embed or run the Node.js server. The existing Kumone UI is reused.

`QishuiPassportSession.swift` uses a per-login ephemeral WebKit session and loads ByteDance's official browser security SDK at runtime from `https://lf-headquarters-speed.yhgfb-cn-static.com/obj/rc-client-security/web/stable/1.0.0.41/bdms.js`. The SDK is not copied into this repository or distributed in the app. The native bridge is independently implemented; no third-party Electron, Chromium signer, or bundled SDK code is incorporated. Browser security protections remain enabled.

Additional protocol reference: `XxHuberrr/Mineradio-paused` commit `d43de565acabfdc1a9c9820a27e81a98ccbebcef`, specifically the Passport session and secondary-verification flow. No Electron/source assets from that GPL-3.0 repository are bundled. The official verification component loads React and ReactDOM 17.0.2 (MIT) from their fixed npm CDN URLs at runtime with SRI; those libraries are not copied into the app.

## SodaM and libresoda

Coda follows the SodaM protocol at [f43a22b](https://github.com/sodahub-org/sodam/tree/f43a22b6239e4fb6c4c099566f6722bcecfb9b60) and the [libresoda 5edd2ff source](https://github.com/sodahub-org/libresoda/tree/5edd2ff3b825f0a16b1e281204822ee06842df9c) it depends on. The original Rust code derives from [music-lib](https://github.com/guohuiyuan/music-lib). The Swift adaptations for search, playback requests and audio decryption are in `Sources/Coda/Core/API/QishuiPlayback.swift` and `Sources/Coda/Core/API/QishuiAudio.swift`. These adaptations retain the upstream GNU Affero General Public License, version 3 or later. The signing service URL and bearer token in `QishuiPlayback.swift` are SodaM's published defaults (`DEFAULT_SIGNER_URL` and `DEFAULT_SIGNER_TOKEN` in `crates/sodam-core/src/config.rs` at f43a22b); they are not Coda credentials. See [libresoda's NOTICE](https://github.com/sodahub-org/libresoda/blob/5edd2ff3b825f0a16b1e281204822ee06842df9c/NOTICE.md) and the bundled [license text](libresoda-AGPL-3.0.txt).

### Listening mode icons

Coda's Qishui home tiles bundle the scene and preference icons from [SodaM's icon assets](https://github.com/sodahub-org/sodam/tree/a378433493a2d9a84e1c1934ac38bdf2847f4607/crates/sodam/assets/icons). Coda tints the original PNG artwork and uses a rasterized copy of SodaM's `music.svg` for the default and fallback icon. The artwork remains subject to its respective licenses and source terms. See [SodaM's notice](https://github.com/sodahub-org/sodam/blob/a378433493a2d9a84e1c1934ac38bdf2847f4607/NOTICE.md).

## qishui-api license

MIT License

Copyright (c) 2026 arrow

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
