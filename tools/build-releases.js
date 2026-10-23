'use strict';

const fs = require('fs');
const path = require('path');

const site = path.resolve(__dirname, '..');
const data = JSON.parse(fs.readFileSync(path.join(site, 'data', 'release-highlights.json'), 'utf8'));
const hotfixes = JSON.parse(fs.readFileSync(path.join(site, 'data', 'hotfixes.json'), 'utf8'));
const base = 'https://github.com/giuxlab-hub/GX-TXT';
const siteBase = 'https://giuxlab-hub.github.io/GX-TXT/';

function escapeHTML(value) {
  return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
function el(tag, className, content) {
  return '<' + tag + (className ? ' class="' + className + '"' : '') + '>' + content + '</' + tag + '>';
}
function assert(condition, message) { if (!condition) throw Error(message); }

assert(data.schema === 'gxtxt.pages.release-highlights/1', 'Unexpected release data schema');
assert(data.sourceFile === 'CHANGELOG.md', 'The official source must remain the public versioned changelog');
assert(data.releases.length === data.coverage.count, 'Release count does not match coverage');
assert(data.releases[0].id === data.coverage.last, 'Latest release must be first');
assert(data.releases[data.releases.length - 1].id === data.coverage.first, 'First public release must be last');
assert(hotfixes.schema === 'gxtxt.pages.hotfix-registry/1' && Array.isArray(hotfixes.entries), 'Invalid hotfix registry');
const seenHotfixes = new Set();
for (const hotfix of hotfixes.entries) {
  assert(/^[a-z0-9-]+$/.test(hotfix.id) && !seenHotfixes.has(hotfix.id), 'Duplicate/invalid hotfix ID');
  assert(data.releases.some(r => r.id === hotfix.target_release_id && r.sha === hotfix.original_commit), 'Hotfix target does not match published source');
  assert(hotfix.exclusive_compatibility === true && hotfix.framework === '0.9.8.10-dev-' + hotfix.target_release_id, 'Invalid version-exclusive hotfix declaration');
  assert(/^[a-f0-9]{64}$/.test(hotfix.asset_sha256) && hotfix.en?.label && hotfix.it?.label, 'Missing verified bilingual hotfix details');
  seenHotfixes.add(hotfix.id);
}
const seenVersions = new Set(), seenShas = new Set();
for (const r of data.releases) {
  assert(/^0[0-9]{2}$|^1[0-9]{2}$/.test(r.id), 'Invalid release ID: ' + r.id);
  assert(/^[a-f0-9]{40}$/.test(r.sha), 'Invalid commit ID for dev-' + r.id);
  assert(!seenVersions.has(r.id) && !seenShas.has(r.sha), 'Duplicate release history entry');
  assert(r.en && r.it, 'Both language editions are required');
  for (const lang of ['en', 'it']) {
    const copy = r[lang];
    assert(copy.title && copy.intro && copy.caveat && Array.isArray(copy.highlights), 'Missing translated content: ' + r.id);
    assert(copy.highlights.length >= 2 && copy.highlights.length <= 6, 'Unexpected highlight count: dev-' + r.id);
  }
  assert(r.doc && !r.doc.includes('..') && !r.doc.startsWith('/') && !r.doc.includes('\\'), 'Unsafe documentation path: ' + r.id);
  seenVersions.add(r.id); seenShas.add(r.sha);
}

const translations = {
  en: {
    title: 'GX-TXT development highlights | dev-' + data.coverage.first + ' to dev-' + data.coverage.last,
    description: 'The development of GX-TXT through ' + data.releases.length + ' public source releases: scientific Datasets, statistics, Curve Digitizer, Workspaces, Worksheet, managed simulation and Replicate curves.',
    heroTag: 'GX-TXT / PUBLIC DEVELOPMENT HISTORY',
    heading: 'How the scientific workbench evolved.',
    lead: 'A curated record of the features that mattered most in each published source version, from the first clean GitHub snapshot to the current milestone covered here.',
    spanLabel: 'PUBLIC REVISIONS', spanValue: data.coverage.count + ' releases',
    rangeLabel: 'COVERED SOURCE HISTORY', rangeValue: 'dev-' + data.coverage.first + ' → dev-' + data.coverage.last,
    sourceLabel: 'PRIMARY REFERENCE', sourceValue: 'Versioned CHANGELOG',
    sourceAction: 'Read complete CHANGELOG ↗',
    repoAction: 'View project source ↗',
    jumpLabel: 'Go to a release',
    labelCurrent: 'LATEST IN THIS TIMELINE',
    detailsLabel: 'Selected changes',
    caveatLabel: 'Scientific scope',
    commitAction: 'View exact Git commit ↗',
    changelogAction: 'CHANGELOG at this revision ↗',
    docAction: 'Relevant public documentation ↗',
    noteHeading: 'Release highlights, not a substitute for the documentation.',
    noteText: 'These summaries are selected from the public GX-TXT CHANGELOG. They describe what was introduced or changed in each source snapshot—not a claim of complete platform coverage, numerical certification or availability of every optional scientific method. For the full contract, consult the corresponding API/manual and source commit.',
    noteLink: 'Browse public API contracts ↗',
    home: 'Overview', workflow: 'Workflow', guides: 'Guides', resources: 'Resources', releases: 'Releases',
    developer: 'Developer', manual: 'Handbook',
    brandSub: 'Scientific workbench',
    skip: 'Skip to content', navigation: 'Main navigation', langLabel: 'Language selection',
    footer: 'Developed by'
  },
  it: {
    title: 'GX-TXT — Novità delle release | dalla dev-' + data.coverage.first + ' alla dev-' + data.coverage.last,
    description: 'Le tappe dello sviluppo pubblico di GX-TXT: Dataset scientifici, statistica, Curve Digitizer, Workspace, Worksheet, simulazioni e curve replicate.',
    heroTag: 'GX-TXT / CRONOLOGIA PUBBLICA DELLO SVILUPPO',
    heading: 'Come si è evoluto il framework scientifico.',
    lead: 'Una selezione delle novità più significative di ogni versione pubblicata, dalla prima copia ripulita su GitHub fino all’ultima release coperta da questa pagina.',
    spanLabel: 'REVISIONI PUBBLICHE', spanValue: data.coverage.count + ' release',
    rangeLabel: 'VERSIONI DOCUMENTATE', rangeValue: 'dev-' + data.coverage.first + ' → dev-' + data.coverage.last,
    sourceLabel: 'FONTE PRINCIPALE', sourceValue: 'CHANGELOG delle versioni',
    sourceAction: 'Consulta il CHANGELOG completo ↗',
    repoAction: 'Vai ai sorgenti ↗',
    jumpLabel: 'Vai a una release',
    labelCurrent: 'ULTIMA VERSIONE DI QUESTA CRONOLOGIA',
    detailsLabel: 'Novità principali',
    caveatLabel: 'Ambito scientifico',
    commitAction: 'Apri il commit esatto ↗',
    changelogAction: 'CHANGELOG di questa versione ↗',
    docAction: 'Documentazione pubblica pertinente ↗',
    noteHeading: 'Le novità non sostituiscono la documentazione.',
    noteText: 'I riepiloghi sono tratti dal CHANGELOG pubblico di GX-TXT. Descrivono le funzionalità introdotte o modificate nei sorgenti di ogni versione, senza implicare il collaudo completo di tutte le piattaforme, la certificazione numerica o la disponibilità di ogni metodo scientifico opzionale. Per i contratti completi consulta l’API, il manuale e il commit della versione.',
    noteLink: 'Esplora le API pubbliche ↗',
    home: 'Panoramica', workflow: 'Come funziona', guides: 'Guide', resources: 'Risorse', releases: 'Release',
    developer: 'Sviluppatore', manual: 'Manuale',
    brandSub: 'Ambiente scientifico',
    skip: 'Vai al contenuto', navigation: 'Navigazione principale', langLabel: 'Selezione della lingua',
    footer: 'Sviluppato da'
  }
};

function render(lang) {
  const t = translations[lang], italian = lang === 'it';
  const root = italian ? '../' : '../';
  const css = italian ? '../../assets/' : '../assets/';
  const canonical = siteBase + (italian ? 'it/releases/' : 'releases/');
  const switchHref = italian ? '../../releases/' : '../it/releases/';
  const otherLanguage = italian ? 'en' : 'it';
  const otherLabel = italian ? 'EN' : 'IT';
  const topLinks = [
    '<a href="' + root + '#workflow">' + escapeHTML(t.workflow) + '</a>',
    '<a href="' + root + '#resources">' + escapeHTML(t.resources) + '</a>',
    '<a href="' + root + '#guides">' + escapeHTML(t.guides) + '</a>',
    '<a href="./" aria-current="page">' + escapeHTML(t.releases) + '</a>',
    '<a href="https://giux-lab.it/" rel="author">Giux-Lab ↗</a>'
  ];
  const nav = data.releases.map(r => '<a href="#dev-' + r.id + '" aria-label="GX-TXT 0.9.8.10-dev-' + r.id + '">dev-' + r.id + '</a>').join('\n');
  const entries = data.releases.map((r, index) => {
    const c = r[lang], version = '0.9.8.10-dev-' + r.id;
    const featured = index === 0;
    const bullets = c.highlights.map(b => '<li>' + escapeHTML(b) + '</li>').join('\n');

    const maintenance = hotfixes.entries.filter(h => h.target_release_id === r.id).map(h => {
      const notice = h[lang];
      return [
        '<div class="release-maintenance" aria-label="' + escapeHTML(notice.label) + '">',
        '<strong>' + escapeHTML(notice.label) + '</strong>',
        '<p>' + escapeHTML(notice.lead) + '</p>',
        
        '<a href="../hotfixes/' + encodeURIComponent(h.id) + '/">' + (italian ? 'Documentazione e download ↗' : 'Documentation and download ↗') + '</a>',
        '</div>'
      ].join('\n');
    }).join('\n');

    const header = [
      '<div class="release-head">',
      '  <div><div class="release-version">' + escapeHTML(version) + '</div>',
      '  <h2>' + escapeHTML(c.title) + '</h2></div>',
      featured ? '  <span class="release-current">' + escapeHTML(t.labelCurrent) + '</span>' : '',
      '</div>'
    ].join('\n');
    const actions = [
      '<div class="release-actions">',
      '<a href="' + base + '/commit/' + r.sha + '">' + escapeHTML(t.commitAction) + '</a>',
      '<a href="' + base + '/blob/' + r.sha + '/CHANGELOG.md">' + escapeHTML(t.changelogAction) + '</a>',
      '<a href="' + base + '/blob/' + r.sha + '/' + r.doc + '">' + escapeHTML(t.docAction) + '</a>',
      '</div>'
    ].join('\n');
    return [
      '<li class="release-entry" id="dev-' + r.id + '">',
      '  <div class="release-marker" aria-hidden="true"><span>' + r.id + '</span></div>',
      '  <article class="release-panel' + (featured ? ' release-featured' : '') + '">',
      header,
      '    <p class="release-intro">' + escapeHTML(c.intro) + '</p>',
      '    <h3 class="release-group-label">' + escapeHTML(t.detailsLabel) + '</h3>',
      '    <ul class="release-bullets">' + bullets + '</ul>',
      '    <div class="release-scope"><span>' + escapeHTML(t.caveatLabel) + '</span><p>' + escapeHTML(c.caveat) + '</p></div>',
      maintenance,
      actions,
      '  </article>',
      '</li>'
    ].join('\n');
  }).join('\n\n');

  const meta = [
    '<!doctype html>',
    '<html lang="' + lang + '">',
    '<head>',
    '  <meta charset="utf-8">',
    '  <meta name="viewport" content="width=device-width, initial-scale=1">',
    '  <meta name="color-scheme" content="dark">',
    '  <meta name="theme-color" content="#0c131d">',
    '  <title>' + escapeHTML(t.title) + '</title>',
    '  <meta name="description" content="' + escapeHTML(t.description) + '">',
    '  <meta name="author" content="Giux-Lab">',
    '  <link rel="canonical" href="' + canonical + '">',
    '  <link rel="alternate" hreflang="en" href="' + siteBase + 'releases/">',
    '  <link rel="alternate" hreflang="it" href="' + siteBase + 'it/releases/">',
    '  <link rel="alternate" hreflang="x-default" href="' + siteBase + 'releases/">',
    '  <link rel="icon" type="image/svg+xml" href="' + css + 'favicon.svg">',
    '  <link rel="stylesheet" href="' + css + 'style.css">',
    '  <link rel="stylesheet" href="' + css + 'releases.css">',
    '  <meta property="og:type" content="website">',
    '  <meta property="og:site_name" content="GX-TXT / Giux-Lab">',
    '  <meta property="og:title" content="' + escapeHTML(t.title) + '">',
    '  <meta property="og:description" content="' + escapeHTML(t.description) + '">',
    '  <meta property="og:url" content="' + canonical + '">',
    '</head>'
  ].join('\n');
  const top = [
    '<body>',
    '  <a class="skip" href="#main">' + escapeHTML(t.skip) + '</a>',
    '  <header>',
    '    <div class="wrap header">',
    '      <a class="brand" href="' + root + '" aria-label="GX-TXT">',
    '        <span class="logo" aria-hidden="true">GX</span>',
    '        <span><strong>GX-TXT</strong><small>' + escapeHTML(t.brandSub) + '</small></span>',
    '      </a>',
    '      <nav aria-label="' + escapeHTML(t.navigation) + '">',
    topLinks.join('\n'),
    '      </nav>',
    '      <div class="lang" aria-label="' + escapeHTML(t.langLabel) + '">',
    italian ? '        <a href="' + switchHref + '" hreflang="en" lang="en">EN</a><span aria-hidden="true">/</span><a href="./" hreflang="it" lang="it" aria-current="page">IT</a>' :
      '        <a href="./" hreflang="en" lang="en" aria-current="page">EN</a><span aria-hidden="true">/</span><a href="' + switchHref + '" hreflang="it" lang="it">IT</a>',
    '      </div>',
    '    </div>',
    '  </header>'
  ].join('\n');
  const body = [
    '<main id="main">',
    '  <section class="wrap release-hero" aria-labelledby="releases-title">',
    '    <div class="release-hero-copy">',
    '      <div class="tag">' + escapeHTML(t.heroTag) + '</div>',
    '      <h1 id="releases-title">' + escapeHTML(t.heading) + '</h1>',
    '      <p class="lead">' + escapeHTML(t.lead) + '</p>',
    '      <div class="buttons">',
    '        <a class="button primary" href="' + base + '/blob/' + data.releases[0].sha + '/CHANGELOG.md">' + escapeHTML(t.sourceAction) + '</a>',
    '        <a class="button secondary" href="' + base + '">' + escapeHTML(t.repoAction) + '</a>',
    '      </div>',
    '    </div>',
    '    <div class="release-stat" aria-label="' + escapeHTML(t.rangeLabel) + '">',
    '      <div class="release-stat-head">GX-TXT / 0.9.8.10</div>',
    '      <div class="release-stat-number">' + data.releases.length.toString().padStart(2,'0') + '</div>',
    '      <div class="release-stat-label">' + escapeHTML(t.spanLabel) + '</div>',
    '      <div class="release-stat-row"><span>' + escapeHTML(t.rangeLabel) + '</span><strong>' + escapeHTML(t.rangeValue) + '</strong></div>',
    '      <div class="release-stat-row"><span>' + escapeHTML(t.sourceLabel) + '</span><strong>' + escapeHTML(t.sourceValue) + '</strong></div>',
    '    </div>',
    '  </section>',
    '  <section class="section release-section" aria-label="' + escapeHTML(t.jumpLabel) + '">',
    '    <div class="wrap">',
    '      <nav class="release-jump" aria-label="' + escapeHTML(t.jumpLabel) + '">',
    '        <span>' + escapeHTML(t.jumpLabel) + '</span>',
    nav,
    '      </nav>',
    '      <ol class="release-timeline">',
    entries,
    '      </ol>',
    '    </div>',
    '  </section>',
    '  <section class="section">',
    '    <div class="wrap release-note">',
    '      <div class="tag">GX-TXT / ' + escapeHTML(t.sourceValue) + '</div>',
    '      <h2>' + escapeHTML(t.noteHeading) + '</h2>',
    '      <p>' + escapeHTML(t.noteText) + '</p>',
    '      <a href="' + base + '/tree/main/docs/api">' + escapeHTML(t.noteLink) + '</a>',
    '    </div>',
    '  </section>',
    '</main>'
  ].join('\n');
  const footer = [
    '<footer><div class="wrap">',
    '<div><p><strong>GX-TXT</strong> — ' + escapeHTML(t.footer) + ' <a href="https://giux-lab.it/" rel="author">Giux-Lab</a>.</p>',
    '<p>Open source · GNU GPL-3.0-or-later · ' + escapeHTML(t.spanValue) + '</p></div>',
    '<div class="links">',
    '<a href="' + root + '">' + escapeHTML(t.home) + '</a>',
    '<a href="' + root + '#guides">' + escapeHTML(t.guides) + '</a>',
    '<a href="https://gxtxt.giux-lab.it/">' + escapeHTML(t.manual) + '</a>',
    '<a href="https://github.com/giuxlab-hub/GX-TXT">' + escapeHTML(t.resources) + '</a>',
    '<a href="' + switchHref + '" hreflang="' + otherLanguage + '" lang="' + otherLanguage + '">' + otherLabel + '</a>',
    '</div></div></footer>',
    '</body>',
    '</html>',
    ''
  ].join('\n');
  return [meta,top,body,footer].join('\n\n');
}
const outputs = [['en','releases/index.html'],['it','it/releases/index.html']];
for (const [lang,relative] of outputs) {
  const output = path.join(site,relative);
  fs.mkdirSync(path.dirname(output),{recursive:true});
  fs.writeFileSync(output,render(lang),'utf8');
  console.log(lang.toUpperCase() + '_RELEASE_PAGE=' + relative + ' BYTES=' + fs.statSync(output).size);
}
console.log('RELEASES_RENDERED=' + data.releases.length + ' VERSION_IDS=' + data.releases.map(x=>x.id).join(','));
