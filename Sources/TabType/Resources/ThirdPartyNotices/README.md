# Bundled third-party notices

KeyWeave preserves TabType's MIT notice in `Contents/Resources/LICENSE` and as a release-archive/image sibling. These additional licenses apply to the identified runtime and data resources; they are not all MIT. The full notices in this directory travel inside the app's resource bundle. `PROVENANCE.json` records exact repository commits, source paths and Git blob matches for inherited datasets.

## Runtime

- **llama.cpp / ggml**, release `b11490`: copyright 2023–2026 The ggml authors, MIT. Full notice: `llama.cpp-MIT.txt`. Source: https://github.com/ggml-org/llama.cpp/tree/b11490.
- **xxHash**, incorporated by that XCFramework build: copyright 2012–2021 Yann Collet, BSD-2-Clause. Full notice: `xxHash-BSD-2-Clause.txt`. Source: https://github.com/ggml-org/llama.cpp/tree/b11490/vendor/hash/xxhash.

## Word-frequency data

The twelve local `frequency_dictionary_*.txt` files are byte-identical to the exact upstream blobs listed in the provenance manifest. Their local filenames differ; their contents were not modified for KeyWeave.

- **English** comes from Wolf Garbe's **SymSpell**, commit `91fe939e9c1259813ee817e95239629c5badf8ec`, `SymSpell/frequency_dictionary_en_82_765.txt`. SymSpell's full MIT notice is `SymSpell-MIT.txt`. Its [frequency-dictionary attribution](https://github.com/wolfgarbe/SymSpell/blob/91fe939e9c1259813ee817e95239629c5badf8ec/README.md#frequency-dictionary) identifies an intersection of **Google Books Ngram** data, licensed **CC BY 3.0**, and **SCOWL** data with its own incorporated notices. We retain attribution to Wolf Garbe/SymSpell, Google Books Ngram and SCOWL. Full texts: `CC-BY-3.0.txt` and `SCOWL-Copyright.txt`. Google source: https://books.google.com/ngrams/datasets. SCOWL source: https://wordlist.aspell.net/. License: https://creativecommons.org/licenses/by/3.0/.
- **Bengali, German, Spanish, French, Hindi, Italian, Malayalam, Portuguese, Tamil, Telugu and Urdu** come from **Hermit Dave / FrequencyWords**, commit `525f9b560de45753a5ea01069454e72e9aa541c6`, `content/2018/` paths listed in the manifest. FrequencyWords identifies **OPUS OpenSubtitles2018** as the corpus source and licenses generated **content CC BY-SA 4.0**. This is distinct from its code's MIT license. Full texts: `CC-BY-SA-4.0.txt` and `FrequencyWords-code-MIT.txt`. Sources: https://github.com/hermitdave/FrequencyWords/tree/525f9b560de45753a5ea01069454e72e9aa541c6 and http://opus.nlpl.eu/OpenSubtitles2018.php. Content license: https://creativecommons.org/licenses/by-sa/4.0/. These lists retain that content license; no additional restrictions are applied.

The bundled SCOWL notice is the complete official v1 notice at `en-wl/wordlist` commit `b22230cc5250887737fdefe9ca4c9d9d01230eaa`, `scowl/Copyright`, including incorporated contributors such as WordNet. The older SCOWL sub-version used to compile SymSpell's dictionary is not documented upstream; this notice snapshot does not claim to identify it.

## Emoji

**GitHub gemoji**, commit `fadaeaf1f1a9be82b321316a6c5502e43138b2f6`, supplies the emoji/shortcode data under MIT; full notice: `gemoji-MIT.txt`. Source: https://github.com/github/gemoji/tree/fadaeaf1f1a9be82b321316a6c5502e43138b2f6. The inherited local JSON is transformed for lookup: first alias becomes `code`, `emoji` becomes `char`, keywords combine unique tags, remaining aliases and lowercased description words; `st` is set for skin-tone support. The exact transform reproduces all 1,870 entries and bytes. That modification is recorded in the manifest.

## Fonts and models

Eight font-specific SIL Open Font License 1.1 notices are retained alongside their font files in the `TabType_TabTypeKit` resource bundle's `Fonts` directory. No model weights are bundled. Any optional manual model download is subject to its own source/license, independently of these application and data notices.
