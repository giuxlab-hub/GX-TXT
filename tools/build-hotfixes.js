'use strict';
const fs=require('fs'),path=require('path');
const site=path.resolve(__dirname,'..'),base='https://giuxlab-hub.github.io/GX-TXT/',github='https://github.com/giuxlab-hub/GX-TXT';
const registry=JSON.parse(fs.readFileSync(path.join(site,'data','hotfixes.json'),'utf8'));
const assert=(c,m)=>{if(!c)throw Error(m)};
const esc=v=>String(v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
assert(registry.schema==='gxtxt.pages.hotfix-registry/1'&&Array.isArray(registry.entries),'Invalid hotfix registry');
const seen=new Set();
function render(h,lang){
 const it=lang==='it',t=h[lang],url=base+(it?'it/':'')+'hotfixes/'+h.id+'/',other=base+(it?'':'it/')+'hotfixes/'+h.id+'/';
 const baseRel=it?'../../../':'../../',relReleases='../../releases/#dev-'+h.target_release_id;
 const tr=it ? {
   tag:'GX-TXT / CORREZIONE DI MANUTENZIONE',back:'Torna alla cronologia',status:'Hotfix sperimentale',exact:'Compatibilità esclusiva',source:'Sorgenti della patch',problem:'Problema affrontato',changes:'Comportamento previsto',install:'Installazione sulla dev-108 originale',verification:'Verifica dopo il riavvio',rollback:'Ripristino della dev-108 originale',limits:'Limiti delle verifiche e della sicurezza',downloaded:'Pacchetto originale verificato',parent:'Commit originale dev-108',patched:'Commit della hotfix',version:'Solo 0.9.8.10-dev-108',none:'Mai sulla dev-109',lic:'GNU GPL-3.0-or-later',tests:'6 test isolati: PASS; GUI reale: non verificata'
 } : {
   tag:'GX-TXT / MAINTENANCE CORRECTION',back:'Back to release history',status:'Experimental hotfix',exact:'Strict compatibility',source:'Patch source',problem:'Problem addressed',changes:'Expected behavior',install:'Install only on unmodified dev-108',verification:'Verify after restart',rollback:'Restore original dev-108',limits:'Validation and security limitations',downloaded:'Verified original package',parent:'Original dev-108 commit',patched:'Hotfix commit',version:'Only 0.9.8.10-dev-108',none:'Never on dev-109',lic:'GNU GPL-3.0-or-later',tests:'6 isolated tests: PASS; live GUI: not verified'
 };
 const installCode=['ROOT="$HOME/gxtxt/gxtxt_pipeline_v09810dev_108"','python3 backport.py --check "$ROOT"','python3 -m unittest -v test_patch','python3 backport.py --apply "$ROOT"'].join('\n');
 const logCode='tail -f "/path/to/viewer-project/derived/viewer_compilation.log"';
 const bullets=(values)=>values.map(v=>'<li>'+esc(v)+'</li>').join('\n');
 const tags=['meta','og:title','og:description'];
 const title='GX-TXT '+h.framework+' — '+t.title;
 const canonical='<link rel="canonical" href="'+url+'">';
 return [
 '<!doctype html>','<html lang="'+lang+'">','<head>',
 '  <meta charset="utf-8">','  <meta name="viewport" content="width=device-width, initial-scale=1">',
 '  <meta name="color-scheme" content="dark">','  <meta name="theme-color" content="#0c131d">',
 '  <meta name="author" content="Giux-Lab">',
 '  <meta name="description" content="'+esc(t.lead)+'">',
 '  <meta property="og:type" content="article">',
 '  <meta property="og:title" content="'+esc(title)+'">',
 '  <meta property="og:description" content="'+esc(t.lead)+'">',
 '  <meta property="og:url" content="'+url+'">',
 '  <title>'+esc(title)+'</title>',
 '  '+canonical,
 '  <link rel="alternate" hreflang="en" href="'+base+'hotfixes/'+h.id+'/">',
 '  <link rel="alternate" hreflang="it" href="'+base+'it/hotfixes/'+h.id+'/">',
 '  <link rel="alternate" hreflang="x-default" href="'+base+'hotfixes/'+h.id+'/">',
 '  <link rel="stylesheet" href="'+baseRel+'assets/style.css">',
 '  <link rel="stylesheet" href="'+baseRel+'assets/hotfixes.css">',
 '  <link rel="icon" type="image/svg+xml" href="'+baseRel+'assets/favicon.svg">',
 '</head>','<body>',
 '  <a class="skip" href="#main">'+(it?'Vai al contenuto':'Skip to content')+'</a>',
 '  <header><div class="wrap header">',
 '    <a class="brand" href="'+baseRel+(it?'it/':'')+'" aria-label="GX-TXT"><span class="logo" aria-hidden="true">GX</span><span><strong>GX-TXT</strong><small>Scientific workbench</small></span></a>',
 '    <nav aria-label="Main navigation"><a href="'+relReleases+'">'+esc(tr.back)+'</a><a href="'+github+'">GitHub ↗</a><a href="https://giux-lab.it/" rel="author">Giux-Lab ↗</a></nav>',
 '    <div class="lang" aria-label="Language selection"><a href="'+(it?other:url)+'" hreflang="en"'+(it?'':' aria-current="page"')+'>EN</a> / <a href="'+(it?url:other)+'" hreflang="it"'+(it?' aria-current="page"':'')+'>IT</a></div>',
 '  </div></header>',
 '  <main id="main">',
 '    <section class="wrap hotfix-hero">',
 '      <div class="tag">'+esc(tr.tag)+'</div>',
 '      <p class="hotfix-id">'+esc(h.framework)+' / '+esc(h.tag)+'</p>',
 '      <h1>'+esc(t.title)+'</h1>',
 '      <p class="lead">'+esc(t.lead)+'</p>',
 '      <div class="hotfix-meta">',
 '        <div><small>'+esc(tr.exact)+'</small><strong>'+esc(tr.version)+'</strong></div>',
 '        <div><small>'+esc(tr.status)+'</small><strong>'+esc(tr.tests)+'</strong></div>',
 '        <div><small>'+esc(tr.none)+'</small><strong>'+esc(h.incompatible_from)+' +</strong></div>',
 '      </div>',
 '      <div class="buttons">',
 '        <a class="button primary" href="'+esc(h.asset_url)+'">'+esc(t.download)+' ↓</a>',
 '        <a class="button secondary" href="'+esc(h.github_release)+'">'+esc(t.release)+' ↗</a>',
 '      </div>',
 '      <p class="hotfix-digest">'+esc(tr.sha)+': <code>'+esc(h.asset_sha256)+'</code> <span>('+(h.asset_bytes.toLocaleString(it?'it-IT':'en-US'))+' bytes)</span></p>',
 '    </section>',
 '    <section class="section"><div class="wrap hotfix-content">',
 '      <h2>'+esc(tr.problem)+'</h2>',
 '      <p>'+esc(t.problem)+'</p>',
 '      <h2>'+esc(tr.changes)+'</h2>',
 '      <ul class="hotfix-list">'+bullets(t.behavior)+'</ul>',
 '      <h2>'+esc(tr.install)+'</h2>',
 '      <p>'+esc(t.install_intro)+'</p>',
 '      <pre><code>'+esc(installCode)+'</code></pre>',
 '      <h2>'+esc(tr.verification)+'</h2>',
 '      <p>'+esc(t.run_intro)+'</p>',
 '      <pre><code>'+esc(logCode)+'</code></pre>',
 '      <h2>'+esc(tr.rollback)+'</h2>',
 '      <p>'+esc(t.rollback)+'</p>',
 '    </div></section>',
 '    <section class="section"><div class="wrap hotfix-content">',
 '      <h2>'+esc(tr.limits)+'</h2>',
 '      <ul class="hotfix-list hotfix-warning">'+bullets(t.caution)+'</ul>',
 '      <div class="hotfix-source">',
 '        <h3>'+esc(tr.source)+'</h3>',
 '        <p>'+esc(tr.parent)+': <a href="'+github+'/commit/'+h.original_commit+'"><code>'+h.original_commit+'</code></a></p>',
 '        <p>'+esc(tr.patched)+': <a href="'+github+'/commit/'+h.hotfix_commit+'"><code>'+h.hotfix_commit+'</code></a></p>',
 '        <p><a href="'+github+'/tree/'+h.hotfix_branch.split('/').map(encodeURIComponent).join('/')+'">'+esc(t.source)+' ↗</a></p>',
 '        <p>'+esc(tr.lic)+'</p>',
 '      </div>',
 '    </div></section>',
 '  </main>',
 '  <footer><div class="wrap"><p>GX-TXT — Giux-Lab · '+esc(tr.lic)+'</p><div class="links"><a href="'+relReleases+'">'+esc(tr.back)+'</a><a href="'+(it?other:url)+'" hreflang="en">EN</a><a href="'+(it?url:other)+'" hreflang="it">IT</a></div></div></footer>',
 '</body>','</html>',''
 ].join('\n');
}
for(const h of registry.entries){
 assert(!seen.has(h.id)&&/^[a-z0-9-]+$/.test(h.id),'Unsafe/duplicate hotfix identifier');seen.add(h.id);
 assert(h.exclusive_compatibility&&h.framework==='0.9.8.10-dev-'+h.target_release_id,'Release scope mismatch');
 assert(h.original_commit==='6371001a219a4e611ce89c8b396c62294e6b979c'&&h.hotfix_commit==='16a2dc488b393865fa85706a3b9d91bbc78b5387','Unexpected source identities');
 assert(h.asset_sha256==='4f90e0ed8b510e442a8d80db219e7abbe80ffd59098afa70e69cb4921fd89885','Unknown published ZIP hash');
 for(const lang of ['en','it']){
  const rel=(lang==='it'?'it/':'')+'hotfixes/'+h.id+'/index.html',f=path.join(site,...rel.split('/'));
  fs.mkdirSync(path.dirname(f),{recursive:true});const html=render(h,lang);
  fs.writeFileSync(f,html,'utf8');console.log('HOTFIX_PAGE='+rel+' BYTES='+Buffer.byteLength(html));
 }
}
console.log('HOTFIXES_RENDERED='+seen.size);
