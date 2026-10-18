# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import json,sys
W=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(W/'_work_gxtxt_dev107/core/python'))
from gxtxt_cpp_policy import validate_source
D=W/'_private_dev107/development/policy-cases';D.mkdir(parents=True,exist_ok=True)
prefix='void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {'
good={
 'numeric_sqrt':prefix+' state.values[0]=host.numeric_sqrt(9); host.number(1,state.values[0]); }',
 'scalar_handler':prefix+' state.counter += 1; host.number(1, event.value); }',
 'numeric_sdk':(W/'_private_dev107/development/probe.cpp').read_text(),
 'helper':'double adjust(double x) { return x+1; }\n'+prefix+' state.values[0] = adjust(event.value); host.number(1,state.values[0]); }',
 'bounded_logic':prefix+' for(int i=0;i<5;++i) { if(i>2) state.counter += 1; } }',
 'literal_include_text':prefix+' host.text(1,"#include <cstdio>"); }',
}
bad={
 'pragma_operator':prefix+'_Pragma("GCC diagnostic ignored \"-Wall\"") }',
 'builtin_macro':prefix+'host.text(1,__FILE__); }',
 'include':'#include <cstdio>\n'+prefix+'}',
 'digraph_include':'%:include <cstdio>\n'+prefix+'}',
 'pragma':'#pragma clang diagnostic ignored "-Wall"\n'+prefix+'}',
 'macro':'#define TYPE double\n'+prefix+'}',
 'extern':'extern "C" int system(const char*);\n'+prefix+' system("true"); }',
 'asm':prefix+' asm("nop"); }',
 'builtin_trap':prefix+' __builtin_trap(); }',
 'math':prefix+' host.number(1,__builtin_sqrt(event.value)); }',
 'declared_math':'double sqrt(double);\n'+prefix+' host.number(1,sqrt(event.value)); }',
 'stdio':prefix+' printf("bad"); }',
 'namespace':'namespace gx { struct Hack {}; }\n'+prefix+'}',
 'global':'int global=0;\n'+prefix+'}',
 'pointer':prefix+' double* p=&state.values[0]; }',
 'out_of_bounds':prefix+' state.values[16]=1; }',
 'negative_index':prefix+' state.values[-1]=1; }',
 'dynamic_index':prefix+' state.values[state.counter]=1; }',
 'private_field':prefix+' host.context_=0; }',
 'cast':prefix+' host.number(1,reinterpret_cast<long>(&state)); }',
 'lambda':prefix+' auto f=[](){return 1;}; host.number(1,f()); }',
 'allocation':prefix+' auto p=new double; }',
 'throw':prefix+' throw 1; }',
 'recursive':'int recurse(int x) {return recurse(x+1);}\n'+prefix+' host.number(1,recurse(0)); }',
 'gnu_statement':prefix+' host.number(1,({1;})); }',
 'raw_function_pointer':prefix+' auto f=&on_event; }',
 'header_import':'import <cstdio>;\n'+prefix+'}',
}
results=[]
for expected,cases in [('PASS',good),('REJECTED',bad)]:
 for name,source in cases.items():
  report=validate_source(source.encode(),D)
  (D/(name+'.json')).write_text(json.dumps(report,indent=2)+'\n')
  results.append({'case':name,'expected':expected,'actual':report['status'],'pass':report['status']==expected and not report['code_generation_invoked'],'diagnostics':report['diagnostics']})
(D/'matrix.json').write_text(json.dumps(results,indent=2)+'\n')
for row in results:
 print(row['case'],row['actual'], 'PASS' if row['pass'] else 'FAIL',row['diagnostics'][:1])
if not all(row['pass'] for row in results):sys.exit(1)
