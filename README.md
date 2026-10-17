# GX-TXT — GitHub Pages

This is the public project presentation site for [GX-TXT](https://github.com/giuxlab-hub/GX-TXT). It is intentionally separate from the scientific framework source on `main`.

- English home: `index.html`
- Italian home: `it/index.html`
- Release highlights, English: `releases/index.html`
- Release highlights, Italian: `it/releases/index.html`
- Shared styles: `assets/style.css`; release-history layout: `assets/releases.css`
- Release-history source: `data/release-highlights.json` (both languages and exact historical Git SHA references)
- Rebuild release pages: `node tools/build-releases.js` (Node.js, no additional package dependency)
- Search metadata: `robots.txt`, `sitemap.xml`
- Static publishing source: `gh-pages` branch, repository root
- Expected project URL: https://giuxlab-hub.github.io/GX-TXT/
- Official developer website: https://giux-lab.it/
- Documentation site: https://gxtxt.giux-lab.it/

Keep references to related external projects grounded in their public Giux-Lab pages. Do not reproduce the original project's private development reports, Session data, internal tests or archival evidence in this site.

The site uses static HTML and CSS with no external JavaScript, tracker or cookie dependencies. Edit both language versions when changing navigation, descriptions or destinations. Do not alter the software source branches to make website-only changes.

**Release-history maintenance:** after each accepted framework version has been published as a separate fast-forward commit to `main`, add a concise English/Italian entry in `data/release-highlights.json`. Ground descriptions in that version’s public `CHANGELOG.md` and applicable API/manual; do not infer features from later releases, silently claim full test coverage, or invent release dates. Verify the exact version commit and documentation path. Run `node tools/build-releases.js`, inspect both generated pages and links, update the coverage text on both home pages and sitemap only when necessary, then publish on `gh-pages` without modifying scientific `main`. The existing Curve Digitizer-only Giux-Lab guide section is separate from this release history.
