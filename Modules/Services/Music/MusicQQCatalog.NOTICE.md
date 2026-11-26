# QQ Music metadata adapter attribution

MusicQQCatalog.swift and the QQ-specific field mapping added to MusicCatalogResolverMapping in MusicPublicCatalog.swift adapt protocol and field-mapping structure from Yingxia / 映匣 (jo32/tvbox-silicon), fixed source commit a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c.

Copyright (C) 2026 jo32 and Yingxia contributors.
License: GPL-3.0-only. Full upstream license is preserved beside this notice as MusicQQCatalog.COPYING, and the repository already preserves LICENSES/Yingxia-GPL-3.0-only.txt and a root NOTICE entry for Yingxia. These adapted portions retain GPL-3.0-only; this notice does not relicense them as MPL-2.0. Distribution of a covered modified version requires corresponding source under the applicable license. No upstream script was executed or shipped by this adapter.

Referenced source: Sources/TVCore/MusicCatalog.swift (anonymous QQ mobile search and song fields), MusicBrowse.swift (charts and playlist plaza), MusicCollectionCatalogs.swift (collection search/detail), MusicLXSources.swift (QQ media-mid resolver field). MusicNetwork.swift and MusicProviders.swift were inspected for boundary context; no audio provider implementation was copied.

Local modifications: independent bounded Foundation JSON parsing; explicit wy/tx identity; caller-owned JS resolver selection; exact-origin redirect policy; ephemeral cookie/credential-free sessions; 15-second request / 25-second resource timeouts; cancellation and incremental 2 MiB response cap; strict missing-schema/service-code failures; QQ artist capability explicitly unsupported; 30 search entries and first 100 detail tracks only. Public catalogue facts are not playback authorization. No audio URL, paid-access bypass, login, credential, or provider fallback is implemented.
