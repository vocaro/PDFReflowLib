# Devanagari source review for #44

## Search and rights

The [Open Logic Project Hindi cumulative working edition](https://zenodo.org/records/21921856)
is a 17-page, CC BY 4.0, machine-assisted Hindi adaptation. The repository record identifies
the frozen Open Logic source, adaptation, license, and limits. Its [direct PDF](https://zenodo.org/records/21921856/files/00_OpenLogic_hi-Deva-IN_CUMULATIVE_READER.pdf)
is 212,719 bytes, SHA-256 `bc7d4f6280d2e3da427715b7ca2df5335e8057ad0c0dcbcadef8c18e27360468`.
It has embedded Devanagari fonts and searchable text. Physical page 5 was checked against its
rendered source: a definition of power sets, two numbered examples, and set notation appear in
the same visual order.

With the current debug CLI, `--language hi --no-ocr` reflows 17/17 pages, recognizes none, and
retains 47 image regions. EPUBCheck reports zero errors or warnings. The XHTML contains 20,225
Devanagari code points and no replacement characters. It retains `प्रश्न set.2` and
`प्रश्न set.3` from physical page 5 and the set notation beside them.

**Not qualified at this native-layer baseline.** Mac PDFKit's inherited text differs from the
source even where Poppler and the rendered page agree. On page 5, source `परिभाषा` becomes
`पिरभाषा` (39 occurrences in the complete EPUB) and source `दिखाइए` becomes `िदखाइए`.
The pre-base vowel sign is emitted before its consonant. A passing contract on just the
surviving identifiers and set symbols would miss the script failure this case was selected to
detect. The repository record also says the translation has no human language review; this
source can check visual/extraction fidelity, not translation accuracy.
The later 180-DPI Hindi OCR admission with original-page reference images and a narrow reviewed
contract is recorded in [script corpus admissions](../script-corpus-admissions-44/record.md).

The newer [211-page working edition](https://zenodo.org/records/21940471) is also CC BY 4.0;
the exact PDF downloaded here is 3,250,779 bytes, SHA-256
`d08e9ea3d8398db2a8f3cd3fc966a9849b41549a9282780ee1725b36b1716781`.
`--language hi --no-ocr` reflows 211/211 pages with 692 image regions, but EPUBCheck reports
32 navigation-order warnings, so it is not a cleaner gate candidate.

An independently authored [26-page Hindi training module](https://www.gov.uk/research-for-development-outputs/getting-stakeholders-on-your-side-training-and-action-planning-workshop)
has a CC BY 3.0 notice on its own physical page 2 and a [stable government PDF](https://assets.publishing.service.gov.uk/media/57a08a7040f0b649740005c4/60435_Training_Module_Hindi.pdf).
It is 1,075,290 bytes, SHA-256 `a6e426ac01722241bda0fd53bc62dd35278e76157e41456b665dd2e82987e4ea`.
The rendered source has clear Devanagari, but its inherited text layer maps those glyphs to
Latin-like garbage: the baseline EPUB contains **zero** Devanagari code points despite 25/26
pages being counted as reflowed (82 image regions, no recognized pages, EPUBCheck zero).
That source is a strong negative case for a future text-layer repair or image fallback, but
cannot yet supply a passing Hindi content contract.
