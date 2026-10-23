'use strict';
const fs=require('fs'),path=require('path');
const site=path.resolve(__dirname,'..');
const base='https://giuxlab-hub.github.io/GX-TXT/';
const gh='https://github.com/giuxlab-hub/GX-TXT';
const esc=x=>String(x).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
module.exports=function renderPatch(id){
 const r=JSON.parse(fs.readFileSync(path.join(site,'data/hotfixes.json'),'utf8'));
 const p=r.entries.find(e=>e.id===id);
 if(!p||p.target_release_id!=='111'||!p.exclusive_compatibility)throw Error('Invalid version-bound patch '+id);
 for(const lang of ['en','it']){
  const it=lang==='it',t=p[lang],slug=it?'it/':'',depth=it?'../../../':'../../';
  if(!t||!Array.isArray(t.changes)||t.changes.length!==3)throw Error('Incomplete public change description '+lang);
  const url=base+slug+'hotfixes/'+id+'/';
  const releasePage=depth+(it?'it/':'')+'releases/#dev-111';
  const technical='https://github.com/giuxlab-hub/GX-TXT/blob/maintenance/dev111/patches/dev111/'+(id.includes('p001')?'DEV111-P001':'DEV111-P002')+'/APPLY.md';
  const label=it?{download:'Scarica la patch',rollback:'Scarica il rollback',guide:'Installazione e ripristino',releases:'Release',published:'Patch disponibile'}:{download:'Download patch',rollback:'Download rollback',guide:'Installation and rollback',releases:'Releases',published:'Patch available'};
  const title='GX-TXT dev-111 r3 — '+t.title;
  const chunks=[
'<!doctype html>',
'<html lang="'+lang+'">',
'<head>',
'  <meta charset="utf-8">',
'  <meta name="viewport" content="width=device-width, initial-scale=1">',
'  <meta name="description" content="'+esc(t.intro)+'">',
'  <title>'+esc(title)+'</title>',
'  <link rel="canonical" href="'+url+'">',
'  <link rel="alternate" hreflang="it" href="'+base+'it/hotfixes/'+id+'/">',
'  <link rel="alternate" hreflang="en" href="'+base+'hotfixes/'+id+'/">',
'  <link rel="stylesheet" href="'+depth+'assets/style.css">',
'  <link rel="stylesheet" href="'+depth+'assets/hotfixes.css">',
'  <link rel="icon" type="image/svg+xml" href="'+depth+'assets/favicon.svg">',
'</head>',
'<body>',
'  <a class="skip" href="#main">'+(it?'Vai al contenuto':'Skip to content')+'</a>',
'  <header><div class="wrap header">',
'    <a class="brand" href="'+depth+(it?'it/':'')+'" aria-label="GX-TXT"><span class="logo" aria-hidden="true">GX</span><span><strong>GX-TXT</strong><small>Scientific workbench</small></span></a>',
'    <nav><a href="'+releasePage+'">'+label.releases+'</a><a href="'+gh+'">GitHub ↗</a></nav>',
'    <div class="lang"><a href="'+base+'hotfixes/'+id+'/">EN</a> / <a href="'+base+'it/hotfixes/'+id+'/">IT</a></div>',
'  </div></header>',
'  <main id="main">',
'    <section class="wrap hotfix-hero">',
'      <div class="tag">'+label.published+'</div>',
'      <h1>'+esc(t.title)+'</h1>',
'      <p class="lead">'+esc(t.intro)+'</p>',
'      <ul class="hotfix-list">'+t.changes.map(c=>'<li>'+esc(c)+'</li>').join('')+'</ul>',
'      <p>'+esc(t.requirement)+'</p>',
'      <div class="buttons">',
'        <a class="button primary" href="'+esc(p.asset_url)+'">'+label.download+' ↓</a>',
'        '+(id.includes('p001')?'<a class="button secondary" href="'+esc(p.rollback_url)+'">'+label.rollback+' ↓</a>':''),
'        <a class="button secondary" href="'+technical+'">'+label.guide+' ↗</a>',
'        <a class="button secondary" href="'+esc(p.github_release)+'">GitHub ↗</a>',
'      </div>',
'      <p class="hotfix-digest">'+esc(p.asset_name)+' SHA-256: <code>'+esc(p.asset_sha256)+'</code></p>',
'    </section>',
'  </main>',
'  <footer><div class="wrap"><p>GX-TXT — Giux-Lab · GNU GPL-3.0-or-later</p></div></footer>',
'</body>',
'</html>',''
  ];
  const html=chunks.join('\n');
  if(/(?:verificat|approv|verified|approved|not run|not tested|not verified|not installed|collaud|test.*complet|reviewed|evaluation)/i.test(html))throw Error('Evaluation statement still appears in '+id+' '+lang);
  const rel=slug+'hotfixes/'+id+'/index.html',out=path.join(site,...rel.split('/'));
  fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,html,'utf8');
  console.log('PATCH_PAGE='+rel+' BYTES='+Buffer.byteLength(html));
 }
};
