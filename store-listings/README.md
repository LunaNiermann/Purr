# Store listings

Canonical English source for every store's marketing copy. `en/` is the source
of truth; the other locale folders are filled by Crowdin (see `crowdin.yml`,
which maps `/store-listings/en/*.txt` to `/store-listings/<lang>/`).

Translations are pulled back into this repo, then copied into each store's own
upload format at release time.

## Files (all plain UTF-8 text)

| File | Store | Limit | Notes |
|------|-------|-------|-------|
| `title.txt` | Play | 30 chars | App name as shown on the listing. |
| `short_description.txt` | Play | 80 chars | The one-line hook. |
| `full_description.txt` | Play | 4000 chars | The main listing body. |
| `extension_summary.txt` | Chrome Web Store / Edge | 132 chars | Short summary line. |
| `extension_description.txt` | Chrome Web Store / Edge | 16000 chars | Full extension description. |

Keep every translation within the limit for its file — some languages run long,
so trim rather than overflow.

## Where each file goes at upload time

- **Play Console**: the three `*_description` / `title` files map to the
  Main store listing fields. For a fastlane/CI upload, mirror them into
  `fastlane/metadata/android/<play-locale>/` (`title.txt`,
  `short_description.txt`, `full_description.txt`).
- **Chrome Web Store**: `extension_summary.txt` → "Summary",
  `extension_description.txt` → "Description", per listing language.
- **Edge Add-ons (Partner Center)**: same two files as Chrome.

## Language set

Matches the app and extension: es, de, fr, it, pt, id, hi, ar, ja, ko.
Store locale codes differ per platform (e.g. Play uses `pt-BR`, `es-ES`);
map `<lang>` to each store's expected code when uploading.
