// SPDX-License-Identifier: GPL-3.0-or-later
// Marshal numerical arrays only; scientific algorithms stay in public Native3D.
gx3de_object* cadNumerical(Tcl_Interp* ip,State& state,const std::string& action,Tcl_Obj* request){
 auto input=cadList(ip,get(ip,request,"points"));if(input.empty()||input.size()>1000000)throw std::runtime_error("Numerical input requires 1..1000000 XYZ points");
 std::vector<gx3de_vec3> points;points.reserve(input.size());for(auto* p:input)points.push_back(cadVector(ip,p,"XYZ"));gx3de_object* result=nullptr;
 if(action=="masked_surface"){
  auto mask=cadList(ip,get(ip,request,"present"));if(mask.size()!=points.size())throw std::runtime_error("Mask shape differs from coordinates");std::vector<uint8_t> present;
  for(auto* m:mask){auto n=integer(str(m),"presence mask");if(n>1)throw std::runtime_error("Presence mask requires 0 or 1");present.push_back(uint8_t(n));}
  auto rows=integer(field(ip,request,"rows"),"rows"),columns=integer(field(ip,request,"columns"),"columns");if(!rows||!columns||rows>points.size()||columns>points.size()||rows*columns!=points.size())throw std::runtime_error("Grid shape differs from coordinates");
  check(gx3de_scientific_masked_surface(state.cadScene,points.data(),present.data(),rows,columns,&result),"construct masked surface");return result;
 }
 if(action=="sweep"){
  auto inputRadii=cadList(ip,get(ip,request,"radii"));if(inputRadii.size()!=points.size())throw std::runtime_error("Sweep needs one radius per path point");std::vector<double> radii;for(auto* r:inputRadii)radii.push_back(number(str(r),"radius"));
  auto sides=integer(field(ip,request,"sides"),"sides"),caps=integer(field(ip,request,"caps"),"caps");if(sides>256||caps>1)throw std::runtime_error("Invalid sweep sides or caps");
  check(gx3de_scientific_sweep(state.cadScene,points.data(),radii.data(),points.size(),uint32_t(sides),uint32_t(caps),cadVector(ip,get(ip,request,"initial_u"),"initial U"),&result),"construct transported-frame sweep");return result;
 }
 auto cellsIn=cadList(ip,get(ip,request,"cells"));if(cellsIn.empty()||cellsIn.size()>1000000)throw std::runtime_error("Need 1..1000000 connected cells");
 std::vector<std::vector<uint64_t>> connectivity(cellsIn.size());std::vector<gx3de_scientific_cell_input> cells(cellsIn.size());
 std::map<std::string,uint32_t> kinds{{"vertex",GX3DE_SCI_CELL_VERTEX},{"line",GX3DE_SCI_CELL_LINE},{"polyline",GX3DE_SCI_CELL_POLYLINE},{"triangle",GX3DE_SCI_CELL_TRIANGLE},{"polygon",GX3DE_SCI_CELL_POLYGON}};
 uint64_t entries=0;for(size_t i=0;i<cells.size();++i){auto kind=kinds.find(field(ip,cellsIn[i],"type"));if(kind==kinds.end()||(action=="indexed_mesh"&&kind->first!="triangle"))throw std::runtime_error("Unsupported numerical cell type");auto ids=cadList(ip,get(ip,cellsIn[i],"indices"));entries+=ids.size();if(entries>6000000)throw std::runtime_error("Connectivity budget exceeded");for(auto* id:ids){auto n=integer(str(id),"point index");if(n>=points.size())throw std::runtime_error("Point index outside XYZ array");connectivity[i].push_back(n);}cells[i].struct_size=sizeof(cells[i]);cells[i].type=kind->second;cells[i].point_ids=connectivity[i].data();cells[i].point_count=ids.size();}
 std::vector<Tcl_Obj*> arraysIn;if(get(ip,request,"arrays"))arraysIn=cadList(ip,get(ip,request,"arrays"));if(arraysIn.size()>64)throw std::runtime_error("Array budget exceeded");
 std::vector<gx3de_scientific_array_input> arrays(arraysIn.size());std::vector<std::vector<double>> values(arrays.size());std::vector<std::string> names(arrays.size());uint64_t total=0;
 for(size_t i=0;i<arrays.size();++i){auto association=field(ip,arraysIn[i],"association");if(association!="point"&&association!="cell")throw std::runtime_error("Array association must be point or cell");auto components=integer(field(ip,arraysIn[i],"components"),"components");if(components<1||components>16)throw std::runtime_error("Array components must be 1..16");auto list=cadList(ip,get(ip,arraysIn[i],"values"));uint64_t tuples=association=="point"?points.size():cells.size();if(list.size()!=tuples*components)throw std::runtime_error("Scientific array shape mismatch");total+=list.size();if(total>16000000)throw std::runtime_error("Scientific array budget exceeded");for(auto* v:list)values[i].push_back(number(str(v),"scientific value"));names[i]=field(ip,arraysIn[i],"name");arrays[i].struct_size=sizeof(arrays[i]);arrays[i].association=association=="point"?GX3DE_SCI_ASSOC_POINT:GX3DE_SCI_ASSOC_CELL;arrays[i].components=components;arrays[i].name_utf8=names[i].c_str();arrays[i].values=values[i].data();arrays[i].tuple_count=tuples;}
 gx3de_scientific_polydata_spec spec{};spec.struct_size=sizeof(spec);spec.points=points.data();spec.point_count=points.size();spec.cells=cells.data();spec.cell_count=cells.size();spec.arrays=arrays.data();spec.array_count=arrays.size();
 check(gx3de_scientific_create_polydata(state.cadScene,&spec,&result),"construct connected scientific PolyData");
 if(action=="indexed_mesh"){gx3de_object* diagnostic=nullptr;auto rc=gx3de_scientific_triangle_mesh_create(result,1000000,134217728,&diagnostic);if(diagnostic)gx3de_object_destroy(diagnostic);if(rc!=GX3DE_OK){gx3de_object_destroy(result);result=nullptr;check(rc,"validate indexed triangle geometry");}}
 return result;
}
