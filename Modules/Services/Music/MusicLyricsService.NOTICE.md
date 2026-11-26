# Yingxia-derived online lyrics adaptation — GPL-3.0-only

`MusicLyricsService.swift` adapts the provider endpoint/response contract from
`Sources/TVCore/MusicLyrics.swift:107-127` in jo32/tvbox-silicon at commit
`a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c`.

Fixed reference file SHA-256:
`6d631aa7a1f291c9f9807019c8c22f466fc5602ba3e6bcd71609c3f397a948bb`.

Upstream: https://github.com/jo32/tvbox-silicon
Licence: GPL-3.0-only; full text remains in
`LICENSES/Yingxia-GPL-3.0-only.txt`. Preserve this notice, the root `NOTICE`,
licence and corresponding source with any redistribution. These adapted portions
are not relicensed as MPL-2.0. Review the combined work before binary distribution.

Readcc changes: direct provider+ID only (no title/companion lookup), guarded
WY numeric ID / QQ songmid extraction from existing MusicJSSong metadata,
strict UTF-8 JSON / canonical base64 / entity decoding, ephemeral credential-free
HTTPS, exact host validation including redirects, incremental 512 KiB cap,
10-second request and 12-second resource timeouts, shared generation-aware
observable model, local-import precedence and offline fixtures.

This source-only adaptation does not execute user scripts, probe embedded services,
reuse upstream credentials, or claim native/runtime validation. The existing LRC
parser/timeline source and root NOTICE are preserved unchanged.
