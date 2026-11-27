# Licensing notes

## Current source license

Source code in the current repository is distributed under the Mozilla Public License 2.0 (`MPL-2.0`), except for files that carry a separate license notice.

The MPL is a file-level copyleft license. When covered source files are modified and distributed, those files and their modifications must remain available under the MPL. Separate files may be combined into a larger work under different terms, subject to the MPL requirements for covered files.

## Earlier releases

Changing the repository license does not revoke licenses already granted. All repository revisions up to and including commit [`87ffc527f5a9d1057591f448d402d07993af920f`](https://github.com/CHANG-JUI-LIN/Yuedu-reader/commit/87ffc527f5a9d1057591f448d402d07993af920f) were published under the MIT License. Later revisions whose root `LICENSE` contains MPL-2.0 are distributed under MPL-2.0, except for separately licensed files.

From commit [`3144df7692d26c4a48ac58b9cdf597cc3e1c807f`](https://github.com/CHANG-JUI-LIN/Yuedu-reader/commit/3144df7692d26c4a48ac58b9cdf597cc3e1c807f) up to and including commit [`11c5efcf0d70cfccc4eae3de16d7d4eaabda4079`](https://github.com/CHANG-JUI-LIN/Yuedu-reader/commit/11c5efcf0d70cfccc4eae3de16d7d4eaabda4079), the root `LICENSE` contained the PolyForm Strict License 1.0.0. The project has returned to MPL-2.0, and those revisions are also available under MPL-2.0, so the MPL grant has no gap.

The complete historical MIT notice is preserved at [`LICENSES/MIT.txt`](LICENSES/MIT.txt) for attribution and notice compliance. Earlier MIT grants remain valid.

## Executable releases

MPL-covered source corresponding to official executable releases is available from the project's [GitHub releases](https://github.com/CHANG-JUI-LIN/Yuedu-reader/releases). The app's About screen links recipients to that location and identifies the MPL-2.0 license.

## Third-party material

Third-party components, sample code, libraries, fonts, documents, and assets remain governed by their own license notices. The project-level MPL license does not replace those notices.

## Integrated Coda music (this Readcc candidate)

`Packages/CodaMusic` vendors Coda v0.1.2 at commit
`7ff2f4546eba29f4b0cb4eda13f693bb2db59c1b`, including its original
AGPL-3.0-or-later notices and separately marked GPL-3.0-only and other
third-party components. The root MPL notice does not relicense these files.
The CodaCore product is actually linked into this application; it is not merely
an unused source reference. Adaptation files and exact binary-capable patches
are provided with this candidate's complete source archive.

Distribution of a combined executable requires checking the applicable
MPL/GPL/AGPL combination terms and providing the complete corresponding source,
modifications, license notices and required build/install information. Attaching
license texts alone is not a determination of compliance. No claim of App Store
eligibility or blanket permission to redistribute every asset is made here.
Coda's original legal documents remain in its own SwiftPM resource bundle and
are accessible from its music About view, without replacing Readcc's root LICENSE.

The upstream SodaM listening-mode PNG artwork had unresolved redistribution
permission. This candidate replaces those 48 resource keys with newly generated
original equalizer artwork; original SVG inputs and a deterministic generator are
included. The original official archive remains an unmodified provenance input.
Other third-party material remains subject to its own notices. No rights in
Coda's or Readcc's names, trademarks or logos are granted by this integration.

## Branding

The source license does not grant rights to the Yuedu names, application icon, logo, screenshots, or other branding. See [TRADEMARKS.md](TRADEMARKS.md).

## Contributions

By submitting a contribution, contributors agree to license that contribution under MPL-2.0 and represent that they have the right to do so. Contributions containing code copied from an incompatible source cannot be accepted.
