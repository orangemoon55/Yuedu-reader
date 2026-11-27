# KuGou playlist protocol references

Kumone's Swift playlist creation, collection, song-addition and unsubscription
requests were checked against the public protocol modules in
https://github.com/MakcRe/KuGouMusicApi:

- `module/playlist_add.js`
- `module/playlist_tracks_add.js`
- `module/playlist_del.js`
- `module/playlist_detail.js`
- `module/playlist_track_all.js`
- `util/crypto.js`

These references supply endpoint names, request fields and the existing
AES-CBC/RSA envelope parameters. Kumone integrates the operations with its
account isolation, catalog identifiers, transport and UI. No JavaScript source
files are bundled. Existing Beans-Music adaptations retain their separate notice.

Cloud-list client identity and device registration were also cross-checked with
https://github.com/moli-lihuashi/Mineradio-Vision (`server/kugou/http.js`,
`server/kugou/favorite.js`, and its cloudlist identity regression test).
KuGou concept-client login tokens require the concept-client app ID, version,
signing salt and RSA key for writes. Device registration signs the base64 AES
ciphertext actually sent; the returned dfid is retained with that device identity.

Collected playlists resolve tracks through the original `list_create_gid` and
`/pubsongs/v2/get_other_list_file_nofilt`, with `begin_idx` pagination. The
account-local collection ID is retained for unsubscription; it is not used
as a private cloud-list file ID.

Read-only account history, listening ranks, private cloud audio and verified
catalog downloads also reference `module/user_history.js`, `user_listen.js`,
`user_cloud.js`, `user_cloud_url.js`, `song_url.js`, `util/helper.js` and
`util/crypto.js`. Those references provide protocol fields, cursor semantics,
the raw RSA listening envelope, the existing cloud AES/RSA envelope and
resource signatures. The Swift adapters use Kumone's account generation checks,
track model, storage validation and existing UI. See `docs/development/kugou-cloud-library.md`.

Real playback reporting additionally references `module/playhistory_upload.js`
and `module/user_listen_report.js` for CSCC endpoint names, event fields,
RSA/AES session envelopes, zlib framing and request signatures. The Swift
implementation measures actual engine progress, owns account-bound event
ordering and deduplication, and independently reconciles history/rank reads.
No upstream JavaScript is bundled. An independent Node crypto/zlib packet
fixture checks framing and encryption across the system and Node zlib versions.
