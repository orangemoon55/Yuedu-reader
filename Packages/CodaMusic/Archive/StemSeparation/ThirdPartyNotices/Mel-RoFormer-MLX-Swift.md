# mel-roformer-mlx-swift and separation checkpoints

Source: https://github.com/xocialize/mel-roformer-mlx-swift
License: MIT. Copyright (c) 2026 Xocialize.

The `StemKit` target (`Sources/StemKit`) adapts the Mel-Band RoFormer model,
STFT/ISTFT, window functions, weight loading and key mapping from this
repository. Changes: the dependency on huggingface/swift-transformers is
removed, mlx-swift 0.30.x API differences are fixed, defaults target the
ZFTurbo vocals checkpoint, and a BS-RoFormer four-stem configuration is added.
Each adapted file keeps the upstream copyright and permission notice in its
header.

## Runtime dependency

- [mlx-swift](https://github.com/ml-explore/mlx-swift) 0.30.6 (MIT, Apple),
  pinned in `Package.swift`. Its transitive dependency
  [swift-numerics](https://github.com/apple/swift-numerics) is Apache-2.0.

## Model weights (downloaded at runtime, not bundled)

- Mel-Band RoFormer vocals v1 and BS-RoFormer four-stem v1.0.12 from
  [ZFTurbo/Music-Source-Separation-Training](https://github.com/ZFTurbo/Music-Source-Separation-Training) (MIT).
- The vocals checkpoint is fetched from the MLX conversion
  [mlx-community/mel-roformer-zfturbo-vocals-v1-mlx](https://huggingface.co/mlx-community/mel-roformer-zfturbo-vocals-v1-mlx).
- The four-stem checkpoint is converted by `Scripts/convert-roformer-checkpoint.py`
  and published as a release asset; see `Sources/StemKit/Weights/ModelStore.swift`.

## License

MIT License

Copyright (c) 2026 Xocialize

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
