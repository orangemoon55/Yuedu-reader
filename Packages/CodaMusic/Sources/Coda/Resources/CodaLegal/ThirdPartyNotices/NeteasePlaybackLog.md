# NetEase client-log protocol

`Sources/Coda/Core/API/NeteasePlaybackLog.swift` adapts the NCBL v3 framing,
ChaCha20 stream encryption, fixed-modulus key wrapping and multipart upload
contract from NeteaseCloudMusicApiEnhanced/api-enhanced, commit
`984cc021b8598cf94c22134f32a8426887fb2de7`, `util/ncbl.js` and
`module/scrobble_v1.js`:

https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced

The upstream utilities credit folltoshe/netease-report-listen-song. Kumone
implements the binary protocol in Swift without a JavaScript runtime. Its
event builder reports actual playback data and omits upstream's fabricated
UI referral chains and hardcoded fee/membership/audio-effect values.

The fixture `Tests/CodaCoreTests/Fixtures/ncbl-reference.json` was generated
offline using that JavaScript implementation, fixed entropy, synthetic
credentials and Node 24 Zstandard compression. It contains no user data.
Production uses standards-compliant raw-block Zstandard frames; independent
Node Zstandard decoding also verified empty, boundary and multi-block frames.

The MIT License (MIT)

Copyright (c) 2013-2022 Binaryify

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
