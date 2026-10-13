% Run through Script Bridge or build policy_octave.json; no Session copying.
% SPDX-License-Identifier: GPL-3.0-or-later
api='EXPERIMENT_DUPLICATION_POLICY_API_v1';
assert(gxtxt_api_has(api) && gxtxt_api_has_operation(api,'validate'));
info=gxtxt_api_call(api,'info',{}); assert(str2double(info.api_version)==1);
p=struct(); p.('meta.id')='example.policy'; p.('config.fields')='gain;calibration_file';
p.('config.gain.type')='number'; p.('config.calibration_file.type')='file';
p.('experiment_duplication.api_version')='1';
p.('experiment_duplication.config_copy')='gain';
p.('experiment_duplication.config_external')='calibration_file';
r=gxtxt_api_call(api,'validate',{p}); v=r.valid; if ischar(v), v=str2double(v); endif; assert(v==1);
p.('config.gain.type')='dataset';
r=gxtxt_api_call(api,'validate',{p}); v=r.valid; if ischar(v), v=str2double(v); endif; assert(v==0);
ctx=gxtxt_context(); current=gxtxt_api_call(api,'module',{ctx.module_id});
assert(strcmp(current.status,'supported'));
legacy=gxtxt_api_call(api,'module',{'analysis.statistics.descriptive'});
assert(strcmp(legacy.status,'unsupported'));
receipt=gxtxt_api_call('SESSION_EXPERIMENT_API_v1','preparation',{});
source=ctx.inputs.primary.dataset_id;
d=gxtxt_api_call('CANONICAL_DATASET_API_v2','describe',{source});
f=fopen(fullfile(ctx.output_dir,'result.txt'),'w');
n=d.row_count; if ischar(n), n=str2double(n); endif;
fprintf(f,'rows=%d\ngain=%g\n',n,ctx.parameters.gain); fclose(f);
fprintf('POLICY_AUTHOR_OCTAVE_PASS %s %s\n',source,current.status);
