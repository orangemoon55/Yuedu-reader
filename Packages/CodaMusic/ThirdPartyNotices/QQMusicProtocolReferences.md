# QQ Music protocol references

The original Swift implementations of playlist creation/subscription, artist
follow lists and artist/album RPCs were checked against these public protocol
implementations:

- https://github.com/jsososo/QQMusicApi at `13b08afd3180cc74d76fff208956b77a560abd22` (GPL-3.0).
- https://github.com/Yyyangshenghao/simple-music at `9e4ef81e0404bb6f39696677a43f6bffb6a29444` (GPL-3.0).

References provide endpoint names, request fields and response shapes. Kumone's
Swift code integrates these operations into its existing isolated account,
transport, model and UI layers. No reference JavaScript/TypeScript source files
are bundled. Existing Beans-Music adaptations retain their separate notice.

The authenticated collection transport and song, album and playlist operations
were adapted from https://github.com/yakult-green-tea/qq-music-api at
`d27a9b55875991e99751719c683cfd0045f3290f` (MIT). The singer operations use
QQ Music's web singer and profile request definitions, which that repository
does not expose. The web request signing and encryption algorithms were
adapted from https://github.com/jixunmoe/qmweb-sign/tree/15305a3cc39f80eb1646ab2bae46468231765736 (MIT).

Search, play-URL and lyric request behavior (`client_search_cp`, `musicu.fcg`
vkey requests) was cross-checked against the reverse-engineering notes in
https://github.com/GitHub-ZC/wp_MusicApi. No source files are bundled.

MIT License

Copyright (c) 2019
Copyright (c) 2024 Jixun Wu

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
