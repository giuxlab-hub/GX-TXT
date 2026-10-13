% Run once in a disposable Session through GX-TXT's Octave Script Workspace.
requirements={'NUMERIC_API_v1@1:math.numeric','DATASET_PUBLICATION_API_v2@2:dataset_publication','PLOT_DATASET_API_v3@3:plot.dataset','GRAPH_WORKFLOW_API_v1@1:graph_workflow','GRAPH_NOTES_API_v1@1:graph_notes','GRAPH_METADATA_API_v1@1:graph_metadata','PLOT_ANNOTATION_API_v1@1:plot_annotation'};
for k=1:numel(requirements),gxtxt_api_require(requirements{k});endfor
x=linspace(0,1,20)';
model=gxtxt_api_call('NUMERIC_API_v1','curve_model_fit',{'pchip',x,x.^2,struct()});
curve=gxtxt_api_call('NUMERIC_API_v1','curve_model_evaluate',{model,linspace(0,1,1000)'});
request=struct('dataset_id','example_combined_octave','contract','table.generic','storage','csv','x_values',curve.x,'y_values',curve.y,'x_variable',struct('variable_id','x','name','x','unit','s','semantic_role','time'),'y_variable',struct('variable_id','y','name','y','unit','V','semantic_role','voltage'),'structured_metadata',struct('processing.model','pchip','experimental.sample','example'));
gxtxt_api_call('DATASET_PUBLICATION_API_v2','publish_series',{request});
spec=gxtxt_api_call('PLOT_DATASET_API_v3','new_spec',{'plot.dataset.xy','Published PCHIP example'});
panel=spec.panels{1};panel.series={struct('id','fit','dataset_id','example_combined_octave','x_variable_id','x','y_variable_id','y','axis','left')};spec.panels={panel};
ref=gxtxt_api_call('PLOT_DATASET_API_v3','create_plot',{spec,'variant'});
identity={ref.module_id,ref.graph_id,ref.variant_id};
gxtxt_api_call('GRAPH_WORKFLOW_API_v1','presentation_set',{identity{:},struct('xy_aspect_mode','xy_equal','background','transparent')});
gxtxt_api_call('PLOT_DATASET_API_v3','render',{ref});
gxtxt_api_call('GRAPH_NOTES_API_v1','write',{ref,sprintf('# PCHIP\nTwenty training points, 1000 output points.')});
gxtxt_api_call('GRAPH_METADATA_API_v1','update',{ref,struct('fit.model','pchip','experimental.sample','example')});
gxtxt_api_call('PLOT_ANNOTATION_API_v1','add',{identity{:},struct('id','example_text','type','text','x',0.2,'y',0.8,'text','PCHIP')});
gxtxt_api_call('PLOT_ANNOTATION_API_v1','update',{identity{:},'example_text',struct('text','Explicit published fit')});
disp(ref);
