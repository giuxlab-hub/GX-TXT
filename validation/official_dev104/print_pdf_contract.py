# SPDX-License-Identifier: GPL-3.0-or-later
"""Finite mixed compositor verification using private materialized inputs.

Poppler/qpdf independently check actual PDF structure, text and raster output.
Native scientific source acquisition and main GUI acceptance are separate.
"""
from pathlib import Path
import hashlib, importlib.util, json, os, subprocess, sys
framework, output=(Path(value).resolve() for value in sys.argv[1:])
if '_private_dev104' not in output.parts: raise ValueError('Private output required')
output.mkdir(exist_ok=False);os.environ['MPLCONFIGDIR']=str(output/'matplotlib')
spec=importlib.util.spec_from_file_location('print_document',framework/'services/printing/gxtxt_print_document.py')
compositor=importlib.util.module_from_spec(spec);spec.loader.exec_module(compositor)
from PIL import Image
from matplotlib import pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
asset=output/'original_source.png';Image.new('RGB',(640,480),(25,90,170)).save(asset)
insert=output/'original_source.pdf'
with PdfPages(insert) as pdf:
    for number in (1,2):
        fig=plt.figure(figsize=(5,4));fig.text(.1,.7,f'ORIGINAL_PDF_PAGE_{number}',fontsize=16);pdf.savefig(fig);plt.close(fig)
sources={path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in (asset,insert)}
columns=[dict(variable_id='distance',label='Distance',unit='m'),dict(variable_id='voltage',label='Voltage',unit='µV'),dict(variable_id='ordinal',label='Unsigned value',unit='')]
table=dict(id='print_table',kind='table',source_id='private_table',caption='Canonical table fixture',columns=columns,
           rows=[[str(index),'1.0000000000000002','18446744073709551615'] for index in range(205)],source_rows=[str(index) for index in range(205)])
text=dict(id='print_text',kind='text',source_id='private_text',caption='Complete UTF-8 text',text='\n'.join(f'LINE_{index:03d} · µV Ω café $literal$' for index in range(80)))
items=[table,dict(id='print_image_a',kind='image',caption='Original image A',path=str(asset)),dict(id='print_image_b',kind='image',caption='Original image B',path=str(asset)),dict(id='print_pdf',kind='pdf',caption='Original vector PDF',path=str(insert)),text]
document=dict(schema='gxtxt.print_materialized.v1',title='Private mixed scientific print',page=dict(paper='A4',orientation='portrait',rows=2,columns=2,margin_mm=12,gap_mm=5,captions=True),items=items)
receipt=compositor.compose(document,output/'portrait.pdf')
assert receipt['page_count']==8,receipt['page_count']
assert receipt['pages'][5]['items']==['print_image_a','print_image_b','print_pdf','print_pdf']
def run(args): return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT,timeout=30)
structure=run(['qpdf','--check',str(output/'portrait.pdf')]);(output/'qpdf.txt').write_text(structure)
info=run(['pdfinfo',str(output/'portrait.pdf')]);(output/'pdfinfo.txt').write_text(info)
assert 'Pages:           8' in info and '595.276 x 841.89 pts (A4)' in info,info
extracted=run(['pdftotext','-layout',str(output/'portrait.pdf'),'-']);(output/'portrait.txt').write_text(extracted)
for token in ('18446744073709551615','1.0000000000000002','µV','ORIGINAL_PDF_PAGE_1','ORIGINAL_PDF_PAGE_2','LINE_000','LINE_079','$literal$','café'):
    assert token in extracted,token
run(['pdftoppm','-f','6','-singlefile','-scale-to','900','-png',str(output/'portrait.pdf'),str(output/'artwork_page')])
with Image.open(output/'artwork_page.png') as rendered:
    assert rendered.height==900 and abs(rendered.width/rendered.height-210/297)<.003
landscape=dict(document,page=dict(document['page'],paper='LETTER',orientation='landscape',rows=1,columns=2))
second=compositor.compose(landscape,output/'landscape.pdf')
info2=run(['pdfinfo',str(output/'landscape.pdf')]);(output/'landscape_pdfinfo.txt').write_text(info2)
assert '792 x 612 pts (letter)' in info2,info2
assert second['page_count']>receipt['page_count']
assert sources=={path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in (asset,insert)}
try: compositor.compose(document,output/'portrait.pdf')
except FileExistsError: pass
else: raise AssertionError('Existing PDF was overwritten')
result=dict(status='PASS',scope='Mixed compositor only; independent Poppler/qpdf checks, not native source/GUI acceptance',portrait=receipt,landscape=second,original_sources=sources,pdf_sha256=hashlib.sha256((output/'portrait.pdf').read_bytes()).hexdigest())

# Text extraction alone cannot detect an opaque overlay hiding source content.
# Inspect the actual Poppler raster's body, excluding page header/footer.
from PIL import ImageChops
body_image=output/'body_visibility'
run(['pdftoppm','-f','1','-l','1','-singlefile','-scale-to','1000','-png',str(output/'portrait.pdf'),str(body_image)])
with Image.open(str(body_image)+'.png').convert('RGB') as actual:
    body=actual.crop((30,100,actual.width-30,actual.height-80))
    ink=sum(1 for red,green,blue in body.getdata() if min(red,green,blue)<160)
    assert ink>3000, f'Actual PDF table body is blank or hidden: {ink} ink pixels'
print('PASS actual rendered table body is visible')

result['rendered_table_ink_pixels']=ink
(output/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS actual mixed PDF pages, units, exact integers/decimals, full UTF-8 text, preserved inserted PDF pages and source SHA')

