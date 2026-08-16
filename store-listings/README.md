# Store listings

Canonical English source for every store's marketing copy, held as a single ARB
of keyed strings. `en/listing.arb` is the source of truth; the other locale
folders (`store-listings/<lang>/listing.arb`) are filled by Crowdin — see
`crowdin.yml`.

> ARB, not `.txt`, on purpose: Crowdin caps how many distinct file formats a
> project may use, and the app already uses `arb`. Reusing that format keeps the
> store listings translatable without bumping the plan. The strings are split
> back into each store's own fields at release time.

Translations are pulled back into this repo, then copied into each store's
upload format at release time.

## Keys (in `listing.arb`)

| Key | Store | Limit | Notes |
|-----|-------|-------|-------|
| `title` | Play | 30 chars | App name as shown on the listing. |
| `shortDescription` | Play | 80 chars | The one-line hook. |
| `fullDescription` | Play | 4000 chars | The main listing body. |
| `extensionSummary` | Chrome Web Store / Edge | 132 chars | Short summary line. |
| `extensionDescription` | Chrome Web Store / Edge | 16000 chars | Full extension description. |

Keep every translation within the limit for its key — some languages run long,
so trim rather than overflow.

## Where each key goes at upload time

- **Play Console**: `title`, `shortDescription`, `fullDescription` map to the
  Main store listing fields. For a fastlane/CI upload, write each into
  `fastlane/metadata/android/<play-locale>/` as `title.txt`,
  `short_description.txt`, `full_description.txt`.
- **Chrome Web Store**: `extensionSummary` → "Summary",
  `extensionDescription` → "Description", per listing language.
- **Edge Add-ons (Partner Center)**: same two keys as Chrome.

## Language set

Matches the app and extension: es, de, fr, it, pt, id, hi, ar, ja, ko.
Store locale codes differ per platform (e.g. Play uses `pt-BR`, `es-ES`);
map `<lang>` to each store's expected code when uploading.
