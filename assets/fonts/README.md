# Bundled fonts

Both families are licensed under the SIL Open Font License 1.1, which permits
bundling in a commercial application provided the fonts themselves are not sold
on their own.

| Family | Weights | Used for | Source |
| --- | --- | --- | --- |
| Plus Jakarta Sans | 500, 600, 700, 800 | Wordmark, headings, display numbers | https://fonts.google.com/specimen/Plus+Jakarta+Sans |
| Inter | 400, 500, 600, 700 | Body copy, labels, table figures | https://fonts.google.com/specimen/Inter |

The files are committed rather than fetched at runtime on purpose. The app has
no network permission and must render identically offline, so a package like
`google_fonts` that downloads on first paint is not an option here.

Only the weights the theme actually references are bundled. Adding a weight
means adding both the `.ttf` and a matching entry under `fonts:` in
`pubspec.yaml` — Flutter will otherwise synthesise it, which looks noticeably
worse than the real cut.
