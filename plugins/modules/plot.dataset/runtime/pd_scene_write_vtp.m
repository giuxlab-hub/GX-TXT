function pd_scene_write_vtp(path, xyz, scalar, verts, lines, polys, rgb, cell_rgb)
  if(nargin<7),rgb=[];endif
  if(nargin<8),cell_rgb=[];endif
  fid=fopen(path,'w');
  if (fid<0), error('plot.dataset interactive: cannot write VTP artifact'); endif
  unwind_protect
    fprintf(fid,'<?xml version="1.0"?>\n<VTKFile type="PolyData" version="0.1" byte_order="LittleEndian">\n<PolyData>\n');
    fprintf(fid,'<Piece NumberOfPoints="%d" NumberOfVerts="%d" NumberOfLines="%d" NumberOfStrips="0" NumberOfPolys="%d">\n',rows(xyz),numel(verts),numel(lines),rows(polys));
    if (!isempty(scalar)||!isempty(rgb))
      if(!isempty(scalar)),fprintf(fid,'<PointData Scalars="scientific_scalar">');else fprintf(fid,'<PointData>');endif
      if(!isempty(scalar))
      fprintf(fid,'<DataArray type="Float64" Name="scientific_scalar" format="ascii">\n');
      fprintf(fid,'%.17g ',scalar); fprintf(fid,'\n</DataArray>\n');
      endif
      if(!isempty(rgb))
        fprintf(fid,'<DataArray type="Float64" Name="display_rgb" NumberOfComponents="3" format="ascii">\n');
        fprintf(fid,'%.17g %.17g %.17g\n',rgb');fprintf(fid,'</DataArray>\n');
      endif
      fprintf(fid,'</PointData>\n');
    endif
    if(!isempty(cell_rgb))
      fprintf(fid,'<CellData><DataArray type="Float64" Name="display_rgb_cell" NumberOfComponents="3" format="ascii">\n');
      fprintf(fid,'%.17g %.17g %.17g\n',cell_rgb');fprintf(fid,'</DataArray></CellData>\n');
    endif
    fprintf(fid,'<Points><DataArray type="Float64" NumberOfComponents="3" format="ascii">\n');
    fprintf(fid,'%.17g %.17g %.17g\n',xyz');
    fprintf(fid,'</DataArray></Points>\n');
    if (!isempty(verts)), write_cells(fid,'Verts',verts(:),1:numel(verts)); endif
    if (!isempty(lines))
      connectivity=[]; offsets=[];
      for k=1:numel(lines)
        connectivity=[connectivity,lines{k}]; offsets(end+1)=numel(connectivity);
      endfor
      write_cells(fid,'Lines',connectivity,offsets);
    endif
    if (!isempty(polys)), write_cells(fid,'Polys',reshape(polys',1,[]),3:3:(3*rows(polys))); endif
    fprintf(fid,'</Piece></PolyData></VTKFile>\n');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_cells(fid, tag, connectivity, offsets)
  fprintf(fid,'<%s><DataArray type="Int64" Name="connectivity" format="ascii">\n',tag);
  fprintf(fid,'%d ',connectivity); fprintf(fid,'\n</DataArray>\n<DataArray type="Int64" Name="offsets" format="ascii">\n');
  fprintf(fid,'%d ',offsets); fprintf(fid,'\n</DataArray></%s>\n',tag);
endfunction
