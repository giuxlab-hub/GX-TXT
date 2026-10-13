// SPDX-License-Identifier: GPL-3.0-or-later
// Numerical geometry construction; retained scientific storage remains GX3DE PolyData.
#include "native_3d_engine_api_v1.h"
#include <vector>
#include <array>
#include <cmath>
#include <new>
namespace {
gx3de_vec3 add(gx3de_vec3 a,gx3de_vec3 b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
gx3de_vec3 sub(gx3de_vec3 a,gx3de_vec3 b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
gx3de_vec3 mul(gx3de_vec3 a,double s){return {a.x*s,a.y*s,a.z*s};}
double dot(gx3de_vec3 a,gx3de_vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
gx3de_vec3 cross(gx3de_vec3 a,gx3de_vec3 b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
bool finite(gx3de_vec3 a){return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z);}
bool unit(gx3de_vec3 &a){double n=std::sqrt(dot(a,a));if(!std::isfinite(n)||n<1e-14)return false;a=mul(a,1/n);return true;}
gx3de_result retain(gx3de_scene* s,const std::vector<gx3de_vec3>& points,const std::vector<std::array<uint64_t,3>>& faces,const std::vector<double>& point_ids,const std::vector<double>& cell_ids,gx3de_object** out){
 std::vector<gx3de_scientific_cell_input> cells(faces.size());
 for(size_t i=0;i<faces.size();++i){cells[i].struct_size=sizeof(cells[i]);cells[i].type=GX3DE_SCI_CELL_TRIANGLE;cells[i].point_ids=faces[i].data();cells[i].point_count=3;}
 gx3de_scientific_array_input arrays[2]{};
 arrays[0].struct_size=sizeof(arrays[0]);arrays[0].association=GX3DE_SCI_ASSOC_POINT;arrays[0].components=1;arrays[0].name_utf8="source_point_id";arrays[0].values=point_ids.data();arrays[0].tuple_count=point_ids.size();
 arrays[1].struct_size=sizeof(arrays[1]);arrays[1].association=GX3DE_SCI_ASSOC_CELL;arrays[1].components=1;arrays[1].name_utf8="source_cell_id";arrays[1].values=cell_ids.data();arrays[1].tuple_count=cell_ids.size();
 gx3de_scientific_polydata_spec spec{};spec.struct_size=sizeof(spec);spec.points=points.data();spec.point_count=points.size();spec.cells=cells.data();spec.cell_count=cells.size();spec.arrays=arrays;spec.array_count=2;
 return gx3de_scientific_create_polydata(s,&spec,out);
}
}
gx3de_result gx3de_scientific_masked_surface(gx3de_scene* scene,const gx3de_vec3* grid,const uint8_t* present,uint64_t rows,uint64_t columns,gx3de_object** out){
 if(!out)return GX3DE_INVALID_ARGUMENT;*out=nullptr;
 if(!scene||!grid||!present||rows<2||columns<2)return GX3DE_INVALID_ARGUMENT;
 if(rows>1000000||columns>1000000||rows>1000000/columns)return GX3DE_RANGE;
 try {
  std::vector<gx3de_vec3> p;std::vector<double> ids,cids;std::vector<uint64_t> map(rows*columns,UINT64_MAX);std::vector<std::array<uint64_t,3>> faces;
  for(uint64_t i=0;i<rows*columns;++i){if(present[i]>1)return GX3DE_INVALID_ARGUMENT;if(!present[i])continue;if(!finite(grid[i]))return GX3DE_INVALID_ARGUMENT;map[i]=p.size();p.push_back(grid[i]);ids.push_back(double(i));}
  for(uint64_t r=0;r+1<rows;++r)for(uint64_t c=0;c+1<columns;++c){uint64_t a=r*columns+c,b=a+1,d=a+columns,e=d+1;if(map[a]==UINT64_MAX||map[b]==UINT64_MAX||map[d]==UINT64_MAX||map[e]==UINT64_MAX)continue;
   faces.push_back({map[a],map[b],map[e]});faces.push_back({map[a],map[e],map[d]});cids.push_back(double(r*(columns-1)+c));cids.push_back(cids.back());}
  if(faces.empty())return GX3DE_DEGENERATE;
  return retain(scene,p,faces,ids,cids,out);
 }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_scientific_sweep(gx3de_scene* scene,const gx3de_vec3* path,const double* radii,uint64_t count,uint32_t sides,uint32_t caps,gx3de_vec3 initial_u,gx3de_object** out){
 if(!out)return GX3DE_INVALID_ARGUMENT;*out=nullptr;
 if(!scene||!path||!radii||count<2||sides<3||caps>1||!finite(initial_u))return GX3DE_INVALID_ARGUMENT;
 if(sides>256||count>1000000/sides)return GX3DE_RANGE;
 try {
  std::vector<gx3de_vec3> tangents(count),p;std::vector<double> ids,cids;std::vector<std::array<uint64_t,3>> faces;
  for(uint64_t i=0;i<count;++i){if(!finite(path[i])||!std::isfinite(radii[i])||radii[i]<=0)return GX3DE_INVALID_ARGUMENT;
   gx3de_vec3 previous{},next{};if(i){previous=sub(path[i],path[i-1]);if(!unit(previous))return GX3DE_DEGENERATE;}if(i+1<count){next=sub(path[i+1],path[i]);if(!unit(next))return GX3DE_DEGENERATE;}
   tangents[i]=i==0?next:i+1==count?previous:add(previous,next);if(!unit(tangents[i]))return GX3DE_DEGENERATE;}
  gx3de_vec3 u=sub(initial_u,mul(tangents[0],dot(initial_u,tangents[0])));if(!unit(u))return GX3DE_DEGENERATE;
  for(uint64_t i=0;i<count;++i){if(i){auto a=tangents[i-1],b=tangents[i],k=cross(a,b);double cosine=dot(a,b);if(cosine<-1+1e-12)return GX3DE_DEGENERATE;
    u=add(add(u,cross(k,u)),mul(cross(k,cross(k,u)),1/(1+cosine)));u=sub(u,mul(b,dot(u,b)));if(!unit(u))return GX3DE_DEGENERATE;}
   auto v=cross(tangents[i],u);for(uint32_t j=0;j<sides;++j){double angle=2*std::acos(-1.)*j/sides;p.push_back(add(path[i],mul(add(mul(u,std::cos(angle)),mul(v,std::sin(angle))),radii[i])));ids.push_back(double(i));}}
  for(uint64_t i=0;i+1<count;++i)for(uint32_t j=0;j<sides;++j){uint64_t a=i*sides+j,b=i*sides+(j+1)%sides,c=b+sides,d=a+sides;faces.push_back({a,b,c});faces.push_back({a,c,d});cids.push_back(double(i));cids.push_back(double(i));}
  if(caps){uint64_t first=p.size();p.push_back(path[0]);ids.push_back(0);uint64_t last=p.size();p.push_back(path[count-1]);ids.push_back(double(count-1));for(uint32_t j=0;j<sides;++j){faces.push_back({first,(j+1)%sides,j});cids.push_back(-1);faces.push_back({last,(count-1)*sides+j,(count-1)*sides+(j+1)%sides});cids.push_back(-2);}}
  return retain(scene,p,faces,ids,cids,out);
 }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}

gx3de_result gx3de_scientific_logical_id(gx3de_object* object,uint32_t association,uint64_t index,uint64_t* id){
 if(!object||!id||(association!=GX3DE_SCI_ASSOC_POINT&&association!=GX3DE_SCI_ASSOC_CELL))return GX3DE_INVALID_ARGUMENT;
 uint64_t array=0;auto rc=gx3de_scientific_array_find(object,association,association==GX3DE_SCI_ASSOC_POINT?"logical_point_id":"logical_cell_id",&array);if(rc!=GX3DE_OK)return rc;
 gx3de_scientific_array_info info{};info.struct_size=sizeof info;rc=gx3de_scientific_array_info_get(object,array,&info);if(rc!=GX3DE_OK)return rc;if(info.components!=1)return GX3DE_INVALID_ARGUMENT;
 double value=0;uint64_t required=0;rc=gx3de_scientific_array_values(object,array,index,1,&value,1,&required);if(rc!=GX3DE_OK)return rc;
 if(!std::isfinite(value)||value<0||value>9007199254740991.||std::floor(value)!=value)return GX3DE_INVALID_ARGUMENT;*id=uint64_t(value);return GX3DE_OK;
}
