'use strict';
const run=require('./build-dev111-simple.js');
module.exports=()=>run('dev111-p001-modules-visibility');
if(require.main===module)module.exports();
