% SPDX-License-Identifier: GPL-3.0-or-later
% Run in Script Workspace with compatible bridge_a/bridge_b table Datasets and
% numeric Variable IDs x/y. Edit the logical IDs for your Session. Outputs are
% create-only, so choose unused public IDs before rerunning.
API='DATASET_TRANSFORM_API_v1';
gxtxt_api_require([API '@1:dataset_transform']);
operations={'project_variables','concat_rows','curve_bundle','extract_family_member'};
sources={ ...
  {struct('dataset_id','bridge_a','variable_ids',{{'x','y'}})}, ...
  {struct('dataset_id','bridge_a'),struct('dataset_id','bridge_b')}, ...
  {struct('dataset_id','bridge_a','member_id','measured','x_variable_id','x','y_variable_id','y'), ...
   struct('dataset_id','bridge_b','member_id','reference','x_variable_id','x','y_variable_id','y')}, ...
  {struct('dataset_id','example_octave_family','variable_ids',{{'x','y'}})}};
outputs={'example_octave_projection','example_octave_concat','example_octave_family','example_octave_member'};
options={struct(),struct(),struct('representation','long'),struct('members',{{'reference'}})};
for index=1:4
  manifest=struct('api_version',1,'operation',operations{index},'sources',{sources{index}}, ...
                 'output',struct('dataset_id',outputs{index},'storage','auto'), ...
                 'options',options{index},'schema_policy',struct());
  plan=gxtxt_api_call(API,'plan',{manifest});
  unwind_protect
    fprintf('%s planned rows: %d\n',operations{index},plan.row_count);
    result=gxtxt_api_call(API,'execute',{plan});
    assert(strcmp(result.dataset_id,outputs{index}));
  unwind_protect_cleanup
    gxtxt_api_call(API,'release_plan',{plan.plan_id});
  end_unwind_protect
endfor
disp('OCTAVE_DATASET_TRANSFORM_EXAMPLES_PASS');
