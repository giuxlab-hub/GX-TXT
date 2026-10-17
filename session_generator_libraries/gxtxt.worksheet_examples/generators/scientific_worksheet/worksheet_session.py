"""Independent deterministic scientific fixture; only documented public GX-TXT APIs."""
# SPDX-License-Identifier: GPL-3.0-or-later
import json
from gxtxt import gxtxt_api_call as call, gxtxt_api_require

def ws(operation,*args):return call('SCIENTIFIC_WORKSHEET_API_v1',operation,list(args))
gxtxt_api_require(['SCIENTIFIC_WORKSHEET_API_v1','PLOT_DATASET_API_v4','DATASET_PUBLICATION_API_v2','SESSION_WORKSPACE_API_v1'])
x=[-2.,-1.,0.,1.,2.]
y=[-3.,-1.,1.,3.,5.]
source=call('DATASET_PUBLICATION_API_v2','publish_series',[{
    'dataset_id':'worksheet.source','contract':'table.generic','storage':'csv',
    'x_variable':{'variable_id':'voltage','unit':'V','dtype':'float64'},
    'y_variable':{'variable_id':'current','unit':'mA','dtype':'float64'},
    'x_values':x,'y_values':y,'provenance':'Independent deterministic generator: current_mA=2*voltage_V+1; no random noise or estimated uncertainty'}])
book=ws('new','Scientific Workbook and Native Charts')
book=ws('rename_sheet',book,'Sheet1','Measurements')
bound=ws('bind_dataset',book,'worksheet.source',{'A':'voltage','B':'current'},1,5)
book=bound['workbook_utf8']
assert bound['row_count']==5
book=ws('define_range',book,'measured_response','B1','B5')
book=ws('set_typed_cell',book,'C1',{'kind':'text','value':'Independent UTF-8 annotation: μA / 雪','unit':''})
book=ws('set_typed_cell',book,'C2',{'kind':'text','value':'Text with tab\tand newline\nremains text','unit':''})
book=ws('set_typed_cell',book,'D1',{'kind':'complex','value':{'shape':[1,1],'real':[1.0],'imaginary':[2.0]},'unit':'V'})
book=ws('set_typed_cell',book,'E1',{'kind':'missing','value':'','unit':'mA'})
book=ws('set_typed_cell',book,'E2',{'kind':'nan','value':'NaN','unit':'mA'})
book=ws('create_sheet',book,'Calibration')
book=ws('set_cell',book,'A1','2')
book=ws('set_cell',book,'B1','Explicit dimensionless gain; no inferred physical calibration')
book=ws('select_sheet',book,'Measurements')
for row in range(1,6):book=ws('set_cell',book,f'F{row}',f'=B{row}*Calibration!$A$1')
for descriptor in [
    {'id':'chart_1','sheet':'Measurements','x_column':'A','y_columns':['B'],'first':1,'last':5,'kind':'line','title':'Measured current','style':{'color':'#1565C0','line_width':1.5,'marker':'circle'},'geometry':[.03,.03,.44,.9]},
    {'id':'chart_2','sheet':'Measurements','x_column':'A','y_columns':['F'],'first':1,'last':5,'kind':'scatter','title':'Explicit gain-derived current','style':{'color':'#AD1457','line_width':1.5,'marker':'square'},'geometry':[.52,.03,.44,.9]}]:
    book=ws('chart_add',book,descriptor)
book=ws('save',book)
identity=ws('identity',book)
assert abs(float(ws('inspect_cell',book,'F1')['value_utf8'])+.006)<1e-12
assert ws('inspect_cell',book,'F1')['unit']=='A'
assert ws('inspect_cell',book,'D1')['kind']=='complex'
assert ws('inspect_cell',book,'E1')['kind']=='missing'
assert ws('inspect_cell',book,'E2')['kind']=='nan'
derived=ws('publish',book,{'voltage':'A','current':'B','gain_current':'F'},1,5,'worksheet.derived','Frozen explicit gain-derived source')
call('SESSION_WORKSPACE_API_v1','rename',[identity['document_id'],'Scientific Workbook and Native Charts'])
spec={'schema':'PLOT_DATASET_PLOTSPEC_v2','graph_type':'cartesian_2d','graph_id':'plot.dataset.xy','title':'Independent Worksheet publication',
 'defaults':{'style':{}},'panels':[{'id':'main','title':'Signed deterministic data','axes':{'x':{'label':'Voltage','scale':'linear'},'y_left':{'label':'Measured current (mA)','scale':'linear'},'y_right':{'label':'Gain-derived current (A)','scale':'linear'}},
 'series':[{'id':'measured','dataset_id':'worksheet.derived','x_variable_id':'voltage','y_variable_id':'current','axis':'left','kind':'line_marker','label':'Measured','style':{'color':'#1565C0'}},
           {'id':'derived','dataset_id':'worksheet.derived','x_variable_id':'voltage','y_variable_id':'gain_current','axis':'right','kind':'scatter','label':'Gain-derived','style':{'color':'#AD1457'}}],
 'annotations':[]}],'output':{}}
plot=call('PLOT_DATASET_API_v4','create_plot',[spec,'variant'])
render=call('PLOT_DATASET_API_v4','render',[plot])
print(json.dumps({'status':'GENERATED','source_dataset':source['dataset_id'],'derived_dataset':derived['dataset_id'],
 'document_id':identity['document_id'],'chart_ids':['chart_1','chart_2'],'native_graph':plot,'render_receipt':render},default=str),flush=True)
