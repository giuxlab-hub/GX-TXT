'use strict';
const fs=require('fs'),path=require('path');
const site=path.resolve(__dirname,'..'),base='https://giuxlab-hub.github.io/GX-TXT/';
const github='https://github.com/giuxlab-hub/GX-TXT';
const registry=JSON.parse(fs.readFileSync(path.join(site,'data','hotfixes.json'),'utf8'));
const id='dev111-p001-modules-visibility';
const patch=registry.entries.find(x=>x.id===id);
const assert=(ok,msg)=>{if(!ok)throw Error(msg)};
const esc=v=>String(v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const li=arr=>arr.map(x=>'      <li>'+esc(x)+'</li>').join('\n');
function render(lang){
 const it=lang==='it',t=patch[lang],url=base+(it?'it/':'')+'hotfixes/'+id+'/',other=base+(it?'':'it/')+'hotfixes/'+id+'/';
 const relative=it?'../../../':'../../',home=it?'it/':'';
 const sections=it?{
 issue:'Correzione introdotta',scope:'Compatibilità e limiti',install:'Installazione e rollback',source:'Sorgenti e verifiche',download:'Scarica patch originale',roll:'Scarica ZIP di rollback',releases:'Cronologia release',status:'Stato',checks:'Verifiche eseguite',scopeLabel:'Solo dev-111 r3'
 }:{issue:'What the patch changes',scope:'Compatibility and limitations',install:'Installation and rollback',source:'Source and verification',download:'Download original patch',roll:'Download original rollback ZIP',releases:'Release history',status:'Status',checks:'Verification performed',scopeLabel:'Only dev-111 r3'};
 const title='GX-TXT dev-111 r3 — DEV111-P001 — '+t.title;
 return [
 '<!doctype html>','<html lang="'+lang+'">','<head>',
 '  <meta charset="utf-8">','  <meta name="viewport" content="width=device-width, initial-scale=1">',
 '  <meta name="color-scheme" content="dark">',
 '  <meta name="author" content="Giux-Lab">',
 '  <meta name="description" content="'+esc(t.lead)+'">',
 '  <meta property="og:type" content="article">',
 '  <meta property="og:title" content="'+esc(title)+'">',
 '  <meta property="og:description" content="'+esc(t.lead)+'">',
 '  <meta property="og:url" content="'+url+'">',
 '  <title>'+esc(title)+'</title>',
 '  <link rel="canonical" href="'+url+'">',
 '  <link rel="alternate" hreflang="en" href="'+base+'hotfixes/'+id+'/">',
 '  <link rel="alternate" hreflang="it" href="'+base+'it/hotfixes/'+id+'/">',
 '  <link rel="alternate" hreflang="x-default" href="'+base+'hotfixes/'+id+'/">',
 '  <link rel="stylesheet" href="'+relative+'assets/style.css">',
 '  <link rel="stylesheet" href="'+relative+'assets/hotfixes.css">',
 '  <link rel="icon" type="image/svg+xml" href="'+relative+'assets/favicon.svg">',
 '</head>','<body>',
 '  <a class="skip" href="#main">'+(it?'Vai al contenuto':'Skip to content')+'</a>',
 '  <header><div class="wrap header">',
 '    <a class="brand" href="'+relative+home+'" aria-label="GX-TXT"><span class="logo" aria-hidden="true">GX</span><span><strong>GX-TXT</strong><small>Scientific workbench</small></span></a>',
 '    <nav aria-label="Main navigation"><a href="../../releases/#dev-111">'+esc(sections.releases)+'</a><a href="'+github+'">GitHub ↗</a></nav>',
 '    <div class="lang" aria-label="Language selection"><a href="'+(it?other:url)+'" hreflang="en">EN</a> / <a href="'+(it?url:other)+'" hreflang="it">IT</a></div>',
 '  </div></header>',
 '  <main id="main">',
 '    <section class="wrap hotfix-hero">',
 '      <div class="tag">GX-TXT / '+(it?'PATCH DI MANUTENZIONE':'MAINTENANCE PATCH')+'</div>',
 '      <p class="hotfix-id">'+esc(patch.framework)+' / '+esc(patch.tag)+'</p>',
 '      <h1>'+esc(t.title)+'</h1>',
 '      <p class="lead">'+esc(t.lead)+'</p>',
 '      <div class="hotfix-meta">',
 '        <div><small>'+esc(sections.scopeLabel)+'</small><strong>0.9.8.10-dev-111 / r3</strong></div>',
 '        <div><small>'+esc(sections.status)+'</small><strong>'+esc(t.statusText)+'</strong></div>',
 '        <div><small>'+esc(sections.checks)+'</small><strong>'+esc(t.testText)+'</strong></div>',
 '      </div>',
 '      <div class="buttons">',
 '        <a class="button primary" href="'+esc(patch.asset_url)+'">'+esc(sections.download)+' ↓</a>',
 '        <a class="button secondary" href="'+esc(patch.rollback_url)+'">'+esc(sections.roll)+' ↓</a>',
 '        <a class="button secondary" href="'+esc(patch.github_release)+'">GitHub Release ↗</a>',
 '      </div>',
 '      <p class="hotfix-digest">DEV111-P001.zip SHA-256: <code>'+patch.asset_sha256+'</code></p>',
 '      <p class="hotfix-digest">ROLLBACK.zip SHA-256: <code>'+patch.rollback_sha256+'</code></p>',
 '    </section>',
 '    <section class="section"><div class="wrap hotfix-content">',
 '      <h2>'+esc(sections.issue)+'</h2>',
 '      <p>'+esc(t.problem)+'</p>',
 '      <ul class="hotfix-list">'+li(t.behavior)+'</ul>',
 '      <h2>'+esc(sections.scope)+'</h2>',
 '      <ul class="hotfix-list hotfix-warning">'+li(t.caution)+'</ul>',
 '      <h2>'+esc(sections.install)+'</h2>',
 '      <p>'+esc(t.install)+'</p>',
 '      <p><a href="'+github+'/blob/maintenance/dev111/patches/dev111/DEV111-P001/APPLY.md">'+esc(t.guide)+' ↗</a></p>',
 '      <p><a href="'+github+'/blob/maintenance/dev111/patches/dev111/DEV111-P001/PUBLIC_COMPATIBILITY.json">'+esc(t.contract)+' ↗</a></p>',
 '      <h2>'+esc(sections.source)+'</h2>',
 '      <p>'+esc(t.sourceNote)+'</p>',
 '      <p>GitHub dev-111 r3: <a href="'+github+'/commit/'+patch.original_commit+'"><code>'+patch.original_commit+'</code></a></p>',
 '      <p>GitHub maintenance: <a href="'+github+'/commit/'+patch.hotfix_commit+'"><code>'+patch.hotfix_commit+'</code></a></p>',
 '      <p><a href="'+github+'/tree/maintenance/dev111/patches/dev111/DEV111-P001">'+esc(t.source)+' ↗</a></p>',
 '    </div></section>',
 '  </main>',
 '  <footer><div class="wrap"><p>GX-TXT — Giux-Lab · GNU GPL-3.0-or-later</p><div class="links"><a href="../../releases/#dev-111">'+esc(sections.releases)+'</a><a href="'+(it?other:url)+'">EN / IT</a></div></div></footer>',
 '</body>','</html>',''
 ].join('\n');
}
function build(){
 assert(patch&&patch.target_release_id==='111'&&patch.original_commit==='4daf135e49378eff1f413310bc17cf32f1928c44','Incorrect dev111-r3 reference');
 assert(patch.hotfix_commit==='5c9d72b4a30e3d464bd263fbf3a3a072c651bbe0','Unknown maintenance commit');
 assert(patch.asset_sha256==='4f40d54d66391a1a0b2051b3c71ecc0e1ed14f614350f568b0664bffd1dd434b','Unknown original ZIP SHA');
 assert(patch.rollback_sha256==='017ccc04f76067c03fcff2bb83add3a89d1fa087dc9670aa2a1526c9f6a439cf','Unknown original rollback SHA');
 assert(patch.installation_status==='NOT_INSTALLED'&&patch.exclusive_compatibility===true,'Unverified patch status/compatibility');
 for(const lang of ['en','it']){
  const rel=(lang==='it'?'it/':'')+'hotfixes/'+id+'/index.html',dest=path.join(site,...rel.split('/'));
  fs.mkdirSync(path.dirname(dest),{recursive:true});const html=render(lang);
  if(/task[-_]?210/i.test(html))throw Error('Internal task nomenclature on public pages');
  fs.writeFileSync(dest,html);
  console.log('DEV111_P001_STATIC_PAGE='+rel+' BYTES='+Buffer.byteLength(html));
 }
}
module.exports=build;
if(require.main===module)build();
