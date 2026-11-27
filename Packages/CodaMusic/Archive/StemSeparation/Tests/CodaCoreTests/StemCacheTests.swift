// Archived with Archive/StemSeparation. These tests exercised `VocalStemCache`
// and `StemSeparation.note`, which were removed from CodaCore. Extracted from
// Tests/CodaCoreTests/BedSplitTests.swift and StemTechniqueTests.swift.
#if false
    // MARK: - The cache

    @Test("four-lane sidecars are their own generation, and v1 still hits")
    func cacheLayout() {
        let source = URL(fileURLWithPath: "/tmp/song.mp3")
        let vocalOnly = VocalStemCache.cacheURL(for: VocalStemRequest(
            source: source, start: 12.5, duration: 8, sampleRate: 44_100, samples: [[]]))
        #expect(vocalOnly.lastPathComponent == "song.mp3.stems-v1-12500-8000.caf")

        let request = StemRequest(source: source, start: 12.5, duration: 8,
                                  sampleRate: 44_100, samples: [[]])
        #expect(VocalStemCache.cacheURL(for: request, lane: .drums).lastPathComponent
                == "song.mp3.stems-v2-12500-8000-drums.caf")
        // Three lanes on disk, not four: `other` is a subtraction.
        #expect(VocalStemCache.storedLanes == [.vocals, .drums, .bass])
        #expect(!VocalStemCache.storedLanes.contains(.other))
        // Both generations are still swept by the same marker, so one `rm`
        // clears the lot.
        #expect(VocalStemCache.isSidecar(vocalOnly))
        #expect(VocalStemCache.isSidecar(VocalStemCache.cacheURL(for: request, lane: .bass)))
    }

    @Test("the derived other makes the four lanes sum back to the mixture exactly")
    func partitionIsExact() {
        let mixture: [[Float]] = [(0..<512).map { Float(sin(Double($0) * 0.05)) }]
        let drums: [[Float]] = [(0..<512).map { Float(0.31 * cos(Double($0) * 0.11)) }]
        let bass: [[Float]] = [(0..<512).map { Float(0.17 * sin(Double($0) * 0.007)) }]
        let vocals: [[Float]] = [(0..<512).map { Float(0.23 * sin(Double($0) * 0.3)) }]
        // A model's own `other` that is deliberately wrong: `completing` must
        // overwrite it rather than trust it.
        let lanes = VocalStemCache.completing(
            [.vocals: vocals, .drums: drums, .bass: bass,
             .other: [[Float](repeating: 99, count: 512)]],
            mixture: mixture)

        let other = try! #require(lanes[.other])
        for i in 0..<512 {
            let sum = vocals[0][i] + drums[0][i] + bass[0][i] + other[0][i]
            #expect(abs(sum - mixture[0][i]) < 1e-6)
        }
    }


    /// The separator's memory notes reach the playback journal.
    ///
    /// `StemSeparator` drops the MLX buffer pool after every window — half a
    /// gigabyte of it, measured — and the only field-visible record that it
    /// happened is a journal line. But the separator lives in StemKit, which
    /// cannot see `PlaybackJournal`: CodaCore is deliberately MLX-free and
    /// the dependency runs one way only. So the host (`StemSetup`) wires
    /// StemKit's hook to `StemSeparation.note`, and
    /// this is the half of that path that is testable without a 64 MiB
    /// checkpoint and a Metal device — that the door is open, and that a line
    /// pushed through it comes out of the journal intact.
    ///
    /// Worth a test because the failure is silent by construction: if this
    /// door closed, nothing would break, no separation would fail, and the
    /// next person asking where the memory went would be back to `vmmap`.
    @Test func theSeparatorsMemoryNotesReachTheJournal() {
        let line = "mlx cache trimmed to 8MB after 14.8s window (freed 512MB)"
        let (_, captured) = PlaybackJournal.tap.capture {
            StemSeparation.note(line)
        }
        #expect(captured == [line])
    }
#endif
