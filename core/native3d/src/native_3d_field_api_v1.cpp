// SPDX-License-Identifier: GPL-3.0-or-later
#include "native_3d_field_api_v1.h"
#include "field_cancellation.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

thread_local const std::atomic<bool>* gx3de_field_cancel_flag=nullptr;
namespace {
using V=gx3de_vec3;
V add(V a,V b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
V mul(V a,double b){return {a.x*b,a.y*b,a.z*b};}
double norm(V a){return std::sqrt(a.x*a.x+a.y*a.y+a.z*a.z);}
bool finite(V a){return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z);}
struct Grid {
    struct Cell {uint32_t type=0;uint64_t id[8]{};V lo{},hi{};};
    gx3de_scientific_grid_info info{};
    uint64_t n[3]{}, count=0;
    double inv[9]{};
    bool unstructured=false;
    std::vector<V> points;
    std::vector<Cell> cells;
    std::vector<double> vectors,scalars;
    double minmag=0;
    bool inverse(){
        double a[9];for(int row=0;row<3;++row)for(int col=0;col<3;++col)
            a[row*3+col]=info.direction[row*3+col]*(&info.spacing.x)[col];
        double d=a[0]*(a[4]*a[8]-a[5]*a[7])-a[1]*(a[3]*a[8]-a[5]*a[6])+a[2]*(a[3]*a[7]-a[4]*a[6]);
        if(!std::isfinite(d)||std::abs(d)<1e-20)return false;
        inv[0]=(a[4]*a[8]-a[5]*a[7])/d;inv[1]=(a[2]*a[7]-a[1]*a[8])/d;inv[2]=(a[1]*a[5]-a[2]*a[4])/d;
        inv[3]=(a[5]*a[6]-a[3]*a[8])/d;inv[4]=(a[0]*a[8]-a[2]*a[6])/d;inv[5]=(a[2]*a[3]-a[0]*a[5])/d;
        inv[6]=(a[3]*a[7]-a[4]*a[6])/d;inv[7]=(a[1]*a[6]-a[0]*a[7])/d;inv[8]=(a[0]*a[4]-a[1]*a[3])/d;
        return true;
    }
    bool sample(V p,V& velocity,double* scalar=nullptr)const{
        if(unstructured){
            auto dot=[](V a,V b){return a.x*b.x+a.y*b.y+a.z*b.z;};
            auto sub=[](V a,V b){return V{a.x-b.x,a.y-b.y,a.z-b.z};};
            auto cross=[](V a,V b){return V{a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};};
            for(const auto& cell:cells){
                if(p.x<cell.lo.x-1e-9||p.y<cell.lo.y-1e-9||p.z<cell.lo.z-1e-9||
                   p.x>cell.hi.x+1e-9||p.y>cell.hi.y+1e-9||p.z>cell.hi.z+1e-9)continue;
                double w[8]{};const uint32_t vertices=cell.type==GX3DE_SCI_CELL_TETRA?4:8;
                if(vertices==4){
                    V a=points[cell.id[0]],b=sub(points[cell.id[1]],a),
                      c=sub(points[cell.id[2]],a),d=sub(points[cell.id[3]],a),q=sub(p,a);
                    double det=dot(b,cross(c,d));if(std::abs(det)<1e-20)continue;
                    w[1]=dot(q,cross(c,d))/det;w[2]=dot(b,cross(q,d))/det;
                    w[3]=dot(b,cross(c,q))/det;w[0]=1-w[1]-w[2]-w[3];
                    if(*std::min_element(w,w+4)<-1e-8||*std::max_element(w,w+4)>1+1e-8)continue;
                }else{
                    /* Standard VTK hexahedron ordering. Invert the trilinear
                     * map with bounded Newton steps; reject folded cells. */
                    static const int sign[8][3]={{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},
                                                  {-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}};
                    double uvw[3]={0,0,0};bool converged=false;
                    for(int iteration=0;iteration<24;++iteration){
                        V mapped{0,0,0},jac[3]={{0,0,0},{0,0,0},{0,0,0}};
                        for(int k=0;k<8;++k){
                            double factors[3]={1+sign[k][0]*uvw[0],1+sign[k][1]*uvw[1],1+sign[k][2]*uvw[2]};
                            double weight=factors[0]*factors[1]*factors[2]/8;
                            mapped=add(mapped,mul(points[cell.id[k]],weight));
                            for(int axis=0;axis<3;++axis){double derivative=sign[k][axis]/8.;
                                for(int other=0;other<3;++other)if(other!=axis)derivative*=factors[other];
                                jac[axis]=add(jac[axis],mul(points[cell.id[k]],derivative));}
                        }
                        V residual=sub(p,mapped);double det=dot(jac[0],cross(jac[1],jac[2]));
                        if(det<=1e-20)break;
                        double delta[3]={dot(residual,cross(jac[1],jac[2]))/det,
                                         dot(jac[0],cross(residual,jac[2]))/det,
                                         dot(jac[0],cross(jac[1],residual))/det};
                        for(int axis=0;axis<3;++axis)uvw[axis]+=delta[axis];
                        if(norm(residual)<1e-10){converged=true;break;}
                        if(std::max({std::abs(uvw[0]),std::abs(uvw[1]),std::abs(uvw[2])})>4)break;
                    }
                    if(!converged||std::max({std::abs(uvw[0]),std::abs(uvw[1]),std::abs(uvw[2])})>1+1e-8)continue;
                    for(int k=0;k<8;++k)w[k]=(1+sign[k][0]*uvw[0])*(1+sign[k][1]*uvw[1])*(1+sign[k][2]*uvw[2])/8;
                }
                velocity={0,0,0};if(scalar)*scalar=0;
                for(uint32_t k=0;k<vertices;++k){uint64_t id=cell.id[k];
                    velocity.x+=w[k]*vectors[3*id];velocity.y+=w[k]*vectors[3*id+1];velocity.z+=w[k]*vectors[3*id+2];
                    if(scalar)*scalar+=w[k]*scalars[id];}
                return finite(velocity)&&(!scalar||std::isfinite(*scalar));
            }
            return false;
        }
        V q{p.x-info.origin.x,p.y-info.origin.y,p.z-info.origin.z};
        double xyz[3]={inv[0]*q.x+inv[1]*q.y+inv[2]*q.z,
                       inv[3]*q.x+inv[4]*q.y+inv[5]*q.z,
                       inv[6]*q.x+inv[7]*q.y+inv[8]*q.z};
        uint64_t lo[3]{};double f[3]{};
        for(int axis=0;axis<3;++axis){
            const double t=xyz[axis]-info.extent[2*axis];
            if(!std::isfinite(t)||t< -1e-9||t>double(n[axis]-1)+1e-9)return false;
            const double clamped=std::max(0.,std::min(double(n[axis]-1),t));
            lo[axis]=std::min(n[axis]-1,uint64_t(std::floor(clamped)));
            if(lo[axis]+1<n[axis])f[axis]=clamped-double(lo[axis]);
        }
        velocity={0,0,0};if(scalar)*scalar=0;
        for(uint64_t iz=0;iz<(n[2]>1?2u:1u);++iz)
        for(uint64_t iy=0;iy<(n[1]>1?2u:1u);++iy)
        for(uint64_t ix=0;ix<(n[0]>1?2u:1u);++ix){
            const uint64_t x=std::min(lo[0]+ix,n[0]-1),y=std::min(lo[1]+iy,n[1]-1),z=std::min(lo[2]+iz,n[2]-1);
            const uint64_t id=x+n[0]*(y+n[1]*z);
            const double w=(ix?f[0]:1-f[0])*(iy?f[1]:1-f[1])*(iz?f[2]:1-f[2]);
            velocity.x+=w*vectors[3*id];velocity.y+=w*vectors[3*id+1];velocity.z+=w*vectors[3*id+2];
            if(scalar)*scalar+=w*scalars[id];
        }
        return finite(velocity)&&(!scalar||std::isfinite(*scalar));
    }
};
enum class Stop {boundary,low,limit,cancelled};
Stop trace(const Grid& g,V seed,double signed_step,uint64_t max_steps,std::vector<V>& line){
    V p=seed;line.push_back(p);
    for(uint64_t step=0;step<max_steps;++step){
        if(gx3de_field_cancelled())return Stop::cancelled;
        auto velocity=[&](V at,V& direction)->Stop{
            if(!g.sample(at,direction))return Stop::boundary;
            double m=norm(direction);if(m<g.minmag||!std::isfinite(m))return Stop::low;
            direction=mul(direction,1.0/m);return Stop::limit;
        };
        V k1{},k2{},k3{},k4{};Stop s=velocity(p,k1);if(s!=Stop::limit)return s;
        s=velocity(add(p,mul(k1,signed_step*0.5)),k2);if(s!=Stop::limit)return s;
        s=velocity(add(p,mul(k2,signed_step*0.5)),k3);if(s!=Stop::limit)return s;
        s=velocity(add(p,mul(k3,signed_step)),k4);if(s!=Stop::limit)return s;
        V next=add(p,mul(add(add(k1,mul(k2,2)),add(mul(k3,2),k4)),signed_step/6));
        V check{};if(!g.sample(next,check))return Stop::boundary;
        line.push_back(next);p=next;
    }
    return Stop::limit;
}
void count_stop(gx3de_field_line_info& info,Stop stop){
    if(stop==Stop::boundary)++info.boundary_stops;
    else if(stop==Stop::low)++info.low_magnitude_stops;
    else ++info.step_limit_stops;
}
gx3de_result read_path_grid(gx3de_object* field,uint64_t vector_index,int64_t scalar_index,
                            uint64_t max_grid_bytes,Grid& grid){
    gx3de_scientific_info si{};si.struct_size=sizeof(si);
    if(gx3de_scientific_info_get(field,&si)!=GX3DE_OK)return GX3DE_UNSUPPORTED;
    grid.unstructured=si.kind==GX3DE_SCIENTIFIC_VTU||si.kind==GX3DE_SCIENTIFIC_UNSTRUCTURED_MEMORY;
    if(!grid.unstructured&&si.kind!=GX3DE_SCIENTIFIC_VTI&&si.kind!=GX3DE_SCIENTIFIC_IMAGE_MEMORY)
        return GX3DE_UNSUPPORTED;
    if(si.point_count>2000000||si.cell_count>2000000)return GX3DE_RANGE;
    if(grid.unstructured){
        grid.count=si.point_count;
        /* Point data, points, and a conservative cell descriptor budget. */
        if(grid.count*(scalar_index>=0?56ull:48ull)+si.cell_count*128ull>max_grid_bytes)return GX3DE_RANGE;
        try{
            grid.points.resize(size_t(grid.count));grid.cells.reserve(size_t(si.cell_count));
            for(uint64_t i=0;i<grid.count;++i){if(gx3de_field_cancelled())return GX3DE_UNSUPPORTED;
                auto rc=gx3de_scientific_point(field,i,0,&grid.points[size_t(i)]);
                if(rc!=GX3DE_OK)return rc;}
            for(uint64_t i=0;i<si.cell_count;++i){if(gx3de_field_cancelled())return GX3DE_UNSUPPORTED;
                gx3de_scientific_cell_info ci{};ci.struct_size=sizeof(ci);
                auto rc=gx3de_scientific_cell_info_get(field,i,&ci);if(rc!=GX3DE_OK)return rc;
                if((ci.type!=GX3DE_SCI_CELL_TETRA||ci.point_count!=4)&&
                   (ci.type!=GX3DE_SCI_CELL_HEXAHEDRON||ci.point_count!=8))return GX3DE_UNSUPPORTED;
                Grid::Cell cell{};cell.type=ci.type;
                for(uint64_t k=0;k<ci.point_count;++k){
                    rc=gx3de_scientific_cell_point_id(field,i,k,&cell.id[k]);if(rc!=GX3DE_OK)return rc;
                    if(cell.id[k]>=grid.count)return GX3DE_INVALID_ARGUMENT;
                    V p=grid.points[size_t(cell.id[k])];
                    if(k==0)cell.lo=cell.hi=p;
                    else{cell.lo={std::min(cell.lo.x,p.x),std::min(cell.lo.y,p.y),std::min(cell.lo.z,p.z)};
                         cell.hi={std::max(cell.hi.x,p.x),std::max(cell.hi.y,p.y),std::max(cell.hi.z,p.z)};}
                }
                grid.cells.push_back(cell);
            }
        }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
    }else{
        grid.info.struct_size=sizeof(grid.info);
        if(gx3de_scientific_grid_info_get(field,&grid.info)!=GX3DE_OK)return GX3DE_UNSUPPORTED;
        grid.count=1;for(int i=0;i<3;++i){const int64_t span=int64_t(grid.info.extent[2*i+1])-grid.info.extent[2*i]+1;
            if(span<1||span>2000000||grid.count>2000000/uint64_t(span))return GX3DE_RANGE;
            grid.n[i]=uint64_t(span);grid.count*=grid.n[i];}
        if(grid.count!=si.point_count||!grid.inverse())return GX3DE_RANGE;
    }
    gx3de_scientific_array_info ai{};ai.struct_size=sizeof(ai);
    if(gx3de_scientific_array_info_get(field,vector_index,&ai)!=GX3DE_OK||
       ai.association!=GX3DE_SCI_ASSOC_POINT||ai.components!=3||ai.tuple_count!=grid.count)return GX3DE_INVALID_ARGUMENT;
    if(scalar_index>=0){ai={};ai.struct_size=sizeof(ai);
        if(gx3de_scientific_array_info_get(field,uint64_t(scalar_index),&ai)!=GX3DE_OK||
           ai.association!=GX3DE_SCI_ASSOC_POINT||ai.components!=1||ai.tuple_count!=grid.count)return GX3DE_INVALID_ARGUMENT;}
    if(!grid.unstructured&&grid.count*(scalar_index>=0?32ull:24ull)>max_grid_bytes)return GX3DE_RANGE;
    try{grid.vectors.resize(size_t(3*grid.count));if(scalar_index>=0)grid.scalars.resize(size_t(grid.count));
        if(gx3de_field_cancelled())return GX3DE_UNSUPPORTED;
        uint64_t required=0;auto rc=gx3de_scientific_array_values(field,vector_index,0,grid.count,
            grid.vectors.data(),grid.vectors.size(),&required);if(rc!=GX3DE_OK)return rc;
        if(scalar_index>=0){rc=gx3de_scientific_array_values(field,uint64_t(scalar_index),0,grid.count,
            grid.scalars.data(),grid.scalars.size(),&required);if(rc!=GX3DE_OK)return rc;}
        for(double v:grid.vectors)if(!std::isfinite(v))return GX3DE_INVALID_ARGUMENT;
        for(double v:grid.scalars)if(!std::isfinite(v))return GX3DE_INVALID_ARGUMENT;
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
bool compatible(const Grid& a,const Grid& b){
    if(a.count!=b.count||a.unstructured!=b.unstructured)return false;
    if(a.unstructured){
        if(a.cells.size()!=b.cells.size()||a.points.size()!=b.points.size())return false;
        for(size_t i=0;i<a.points.size();++i){V x=a.points[i],y=b.points[i];
            if(norm({x.x-y.x,x.y-y.y,x.z-y.z})>1e-12*std::max({1.,norm(x),norm(y)}))return false;}
        for(size_t i=0;i<a.cells.size();++i){const auto& x=a.cells[i];const auto& y=b.cells[i];
            if(x.type!=y.type)return false;
            for(int k=0;k<(x.type==GX3DE_SCI_CELL_TETRA?4:8);++k)if(x.id[k]!=y.id[k])return false;}
        return true;
    }
    for(int i=0;i<3;++i)if(a.n[i]!=b.n[i])return false;
    for(int i=0;i<6;++i)if(a.info.extent[i]!=b.info.extent[i])return false;
    const double x[15]={a.info.origin.x,a.info.origin.y,a.info.origin.z,
        a.info.spacing.x,a.info.spacing.y,a.info.spacing.z,
        a.info.direction[0],a.info.direction[1],a.info.direction[2],a.info.direction[3],a.info.direction[4],
        a.info.direction[5],a.info.direction[6],a.info.direction[7],a.info.direction[8]};
    const double y[15]={b.info.origin.x,b.info.origin.y,b.info.origin.z,
        b.info.spacing.x,b.info.spacing.y,b.info.spacing.z,
        b.info.direction[0],b.info.direction[1],b.info.direction[2],b.info.direction[3],b.info.direction[4],
        b.info.direction[5],b.info.direction[6],b.info.direction[7],b.info.direction[8]};
    for(int i=0;i<15;++i)if(std::abs(x[i]-y[i])>1e-12*std::max({1.0,std::abs(x[i]),std::abs(y[i])}))return false;
    return true;
}
bool sample_time(const Grid& a,const Grid& b,V p,double alpha,V& velocity,double* scalar){
    V va{},vb{};double sa=0,sb=0;
    if(!a.sample(p,va,scalar?&sa:nullptr)||!b.sample(p,vb,scalar?&sb:nullptr))return false;
    velocity=add(mul(va,1-alpha),mul(vb,alpha));
    if(scalar)*scalar=sa*(1-alpha)+sb*alpha;
    return finite(velocity)&&(!scalar||std::isfinite(*scalar));
}
} // namespace

extern "C" GX3DE_API gx3de_result gx3de_field_source_info_get(gx3de_object* field,gx3de_field_source_info* out){
    if(!field||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    gx3de_scientific_info source{};source.struct_size=sizeof(source);
    auto rc=gx3de_scientific_info_get(field,&source);if(rc!=GX3DE_OK)return rc;
    gx3de_field_source_info info{};info.struct_size=sizeof(info);info.scientific_kind=source.kind;
    if(source.kind==GX3DE_SCIENTIFIC_VTI||source.kind==GX3DE_SCIENTIFIC_IMAGE_MEMORY){
        info.supported_cells=source.cell_count;
    }else if(source.kind==GX3DE_SCIENTIFIC_VTU||source.kind==GX3DE_SCIENTIFIC_UNSTRUCTURED_MEMORY){
        for(uint64_t i=0;i<source.cell_count;++i){gx3de_scientific_cell_info cell{};cell.struct_size=sizeof(cell);
            rc=gx3de_scientific_cell_info_get(field,i,&cell);if(rc!=GX3DE_OK)return rc;
            if((cell.type==GX3DE_SCI_CELL_TETRA&&cell.point_count==4)||
               (cell.type==GX3DE_SCI_CELL_HEXAHEDRON&&cell.point_count==8))++info.supported_cells;
            else{++info.unsupported_cells;if(!info.first_unsupported_cell_type)info.first_unsupported_cell_type=cell.type;}
        }
    }else return GX3DE_UNSUPPORTED;
    *out=info;return GX3DE_OK;
}

extern "C" GX3DE_API gx3de_result gx3de_field_lines_create(gx3de_scene* scene,const gx3de_field_line_spec* spec,
                                                               gx3de_object** out,gx3de_field_line_info* info){
    if(!scene||!spec||!out||!info||spec->struct_size<sizeof(*spec)||info->struct_size<sizeof(*info))return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;gx3de_field_line_info result{};result.struct_size=sizeof(result);
    if(!spec->field||spec->seed_kind<GX3DE_FIELD_SEED_POINTS||spec->seed_kind>GX3DE_FIELD_SEED_PLANE||
       spec->direction<GX3DE_FIELD_FORWARD||spec->direction>GX3DE_FIELD_BOTH||
       !std::isfinite(spec->step_size)||spec->step_size<=0||!std::isfinite(spec->min_vector_magnitude)||spec->min_vector_magnitude<=0||
       !std::isfinite(spec->tube_radius)||spec->tube_radius<0||spec->max_steps_per_direction<1||spec->max_steps_per_direction>100000||
       spec->max_output_points<2||spec->max_output_points>1000000||
       spec->max_memory_bytes<1024||spec->max_memory_bytes>512ull*1024*1024)return GX3DE_INVALID_ARGUMENT;
    gx3de_scene* owner=nullptr;
    if(gx3de_object_scene_get(spec->field,&owner)!=GX3DE_OK)return GX3DE_INVALID_ARGUMENT;
    if(owner!=scene)return GX3DE_WRONG_OWNER;
    uint64_t seed_count=spec->seed_kind==GX3DE_FIELD_SEED_POINTS?spec->seed_count:
                        spec->seed_kind==GX3DE_FIELD_SEED_LINE?spec->seed_u_count:uint64_t(spec->seed_u_count)*spec->seed_v_count;
    if(!seed_count||seed_count>10000||(spec->seed_kind==GX3DE_FIELD_SEED_POINTS&&!spec->seed_points)||
       (spec->seed_kind!=GX3DE_FIELD_SEED_POINTS&&(!finite(spec->seed_origin)||!finite(spec->seed_u)||
       (spec->seed_kind==GX3DE_FIELD_SEED_PLANE&&!finite(spec->seed_v)))))return GX3DE_INVALID_ARGUMENT;
    result.requested_seeds=seed_count;
    const bool has_scalar=spec->scalar_array>=0;
    const uint64_t output_bytes=spec->max_output_points*128ull+seed_count*256ull;
    if(output_bytes>=spec->max_memory_bytes)return GX3DE_RANGE;
    Grid grid;
    auto read_rc=read_path_grid(spec->field,spec->vector_array,spec->scalar_array,
                                spec->max_memory_bytes-output_bytes,grid);
    if(read_rc!=GX3DE_OK)return read_rc;
    try{
        grid.minmag=spec->min_vector_magnitude;
        std::vector<V> points;std::vector<double> scalar_values;std::vector<std::vector<uint64_t>> ids;
        points.reserve(size_t(std::min(spec->max_output_points,seed_count*16)));
        for(uint64_t i=0;i<seed_count;++i){
            if(gx3de_field_cancelled())return GX3DE_UNSUPPORTED;
            V seed=spec->seed_kind==GX3DE_FIELD_SEED_POINTS?spec->seed_points[i]:
                   add(spec->seed_origin,add(mul(spec->seed_u,double(i%spec->seed_u_count)),
                       spec->seed_kind==GX3DE_FIELD_SEED_PLANE?mul(spec->seed_v,double(i/spec->seed_u_count)):V{0,0,0}));
            if(!finite(seed))return GX3DE_INVALID_ARGUMENT;
            std::vector<V> forward,backward,combined;
            if(spec->direction!=GX3DE_FIELD_BACKWARD){auto stop=trace(grid,seed,spec->step_size,spec->max_steps_per_direction,forward);
                if(stop==Stop::cancelled)return GX3DE_UNSUPPORTED;count_stop(result,stop);}
            if(spec->direction!=GX3DE_FIELD_FORWARD){auto stop=trace(grid,seed,-spec->step_size,spec->max_steps_per_direction,backward);
                if(stop==Stop::cancelled)return GX3DE_UNSUPPORTED;count_stop(result,stop);}
            if(!backward.empty()){
                for(size_t k=backward.size();k>0;--k)combined.push_back(backward[k-1]);
                if(!forward.empty())combined.pop_back();
            }
            combined.insert(combined.end(),forward.begin(),forward.end());
            if(combined.size()<2)continue;
            if(combined.size()>spec->max_output_points-points.size())return GX3DE_RANGE;
            std::vector<uint64_t> line;line.reserve(combined.size());
            for(V p:combined){line.push_back(points.size());points.push_back(p);
                if(has_scalar){V v{};double scalar=0;if(!grid.sample(p,v,&scalar))return GX3DE_DEGENERATE;scalar_values.push_back(scalar);}}
            ids.push_back(std::move(line));++result.created_lines;
        }
        result.output_points=points.size();*info=result;
        if(ids.empty())return GX3DE_NOT_FOUND;
        std::vector<gx3de_scientific_cell_input> cells;cells.reserve(ids.size());
        for(auto& line:ids){gx3de_scientific_cell_input c{};c.struct_size=sizeof(c);c.type=GX3DE_SCI_CELL_POLYLINE;
            c.point_ids=line.data();c.point_count=line.size();cells.push_back(c);}
        gx3de_scientific_array_input scalar{};scalar.struct_size=sizeof(scalar);scalar.association=GX3DE_SCI_ASSOC_POINT;
        scalar.components=1;scalar.name_utf8="field_scalar";scalar.values=scalar_values.data();scalar.tuple_count=scalar_values.size();
        gx3de_scientific_polydata_spec create{};create.struct_size=sizeof(create);create.points=points.data();create.point_count=points.size();
        create.cells=cells.data();create.cell_count=cells.size();create.arrays=has_scalar?&scalar:nullptr;create.array_count=has_scalar?1:0;
        auto rc=gx3de_scientific_create_polydata(scene,&create,out);if(rc!=GX3DE_OK)return rc;
        rc=gx3de_object_set_parent(*out,spec->field);
        if(rc!=GX3DE_OK){gx3de_object_destroy(*out);*out=nullptr;return rc;}
        gx3de_scientific_field_roles roles{};roles.struct_size=sizeof(roles);roles.scalar_array=has_scalar?0:-1;
        roles.vector_array=-1;roles.radius_array=-1;roles.tube_radius=spec->tube_radius;
        rc=gx3de_scientific_field_roles_set(*out,&roles);if(rc!=GX3DE_OK){gx3de_object_destroy(*out);*out=nullptr;return rc;}
        if(has_scalar){gx3de_object_style style{};style.struct_size=sizeof(style);
            if(gx3de_object_style_get(*out,&style)==GX3DE_OK){style.scalar_coloring=1;
                rc=gx3de_object_style_set(*out,&style);
                if(rc!=GX3DE_OK){gx3de_object_destroy(*out);*out=nullptr;return rc;}}}
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}

extern "C" GX3DE_API gx3de_result gx3de_field_slice_create(gx3de_scene* scene,const gx3de_field_slice_spec* spec,
                                                               gx3de_object** out){
    if(!scene||!spec||!out||spec->struct_size<sizeof(*spec))return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    if(!spec->field||spec->u_count<2||spec->v_count<2||spec->u_count>1024||spec->v_count>1024||
       uint64_t(spec->u_count)*spec->v_count>1000000||!finite(spec->origin)||!finite(spec->u_step)||!finite(spec->v_step)||
       norm(spec->u_step)<1e-15||norm(spec->v_step)<1e-15||
       spec->max_memory_bytes<1024||spec->max_memory_bytes>512ull*1024*1024)return GX3DE_INVALID_ARGUMENT;
    gx3de_scene* owner=nullptr;
    if(gx3de_object_scene_get(spec->field,&owner)!=GX3DE_OK)return GX3DE_INVALID_ARGUMENT;
    if(owner!=scene)return GX3DE_WRONG_OWNER;
    gx3de_scientific_info si{};si.struct_size=sizeof(si);
    if(gx3de_scientific_info_get(spec->field,&si)!=GX3DE_OK||
       (si.kind!=GX3DE_SCIENTIFIC_VTI&&si.kind!=GX3DE_SCIENTIFIC_IMAGE_MEMORY))return GX3DE_UNSUPPORTED;
    Grid grid;grid.info.struct_size=sizeof(grid.info);
    if(gx3de_scientific_grid_info_get(spec->field,&grid.info)!=GX3DE_OK)return GX3DE_UNSUPPORTED;
    grid.count=1;for(int i=0;i<3;++i){const int64_t span=int64_t(grid.info.extent[2*i+1])-grid.info.extent[2*i]+1;
        if(span<1||span>2000000||grid.count>2000000/uint64_t(span))return GX3DE_RANGE;
        grid.n[i]=uint64_t(span);grid.count*=grid.n[i];}
    if(grid.count!=si.point_count||!grid.inverse())return GX3DE_RANGE;
    gx3de_scientific_array_info ai{};ai.struct_size=sizeof(ai);
    if(gx3de_scientific_array_info_get(spec->field,spec->scalar_array,&ai)!=GX3DE_OK||
       ai.association!=GX3DE_SCI_ASSOC_POINT||ai.components!=1||ai.tuple_count!=grid.count)return GX3DE_INVALID_ARGUMENT;
    uint64_t points_count=uint64_t(spec->u_count)*spec->v_count;
    uint64_t cells_count=2ull*(spec->u_count-1)*(spec->v_count-1);
    uint64_t memory=grid.count*32ull+points_count*(sizeof(V)+sizeof(double))+
                    cells_count*(sizeof(gx3de_scientific_cell_input)+3*sizeof(uint64_t));
    if(memory>spec->max_memory_bytes)return GX3DE_RANGE;
    try{
        grid.scalars.resize(size_t(grid.count));grid.vectors.resize(size_t(3*grid.count),0);
        uint64_t required=0;auto rc=gx3de_scientific_array_values(spec->field,spec->scalar_array,0,grid.count,
            grid.scalars.data(),grid.scalars.size(),&required);if(rc!=GX3DE_OK)return rc;
        for(double value:grid.scalars)if(!std::isfinite(value))return GX3DE_INVALID_ARGUMENT;
        std::vector<V> points;std::vector<double> values;points.reserve(size_t(points_count));values.reserve(size_t(points_count));
        for(uint32_t v=0;v<spec->v_count;++v)for(uint32_t u=0;u<spec->u_count;++u){
            if(gx3de_field_cancelled())return GX3DE_UNSUPPORTED;
            V p=add(spec->origin,add(mul(spec->u_step,double(u)),mul(spec->v_step,double(v))));
            V unused{};double value=0;if(!grid.sample(p,unused,&value))return GX3DE_RANGE;
            points.push_back(p);values.push_back(value);
        }
        std::vector<std::array<uint64_t,3>> ids;ids.reserve(size_t(cells_count));
        for(uint32_t v=0;v+1<spec->v_count;++v)for(uint32_t u=0;u+1<spec->u_count;++u){
            uint64_t p=uint64_t(v)*spec->u_count+u;
            ids.push_back({p,p+1,p+spec->u_count+1});ids.push_back({p,p+spec->u_count+1,p+spec->u_count});}
        std::vector<gx3de_scientific_cell_input> cells;cells.reserve(ids.size());
        for(auto& triangle:ids){gx3de_scientific_cell_input c{};c.struct_size=sizeof(c);c.type=GX3DE_SCI_CELL_TRIANGLE;
            c.point_ids=triangle.data();c.point_count=3;cells.push_back(c);}
        gx3de_scientific_array_input scalar{};scalar.struct_size=sizeof(scalar);scalar.association=GX3DE_SCI_ASSOC_POINT;
        scalar.components=1;scalar.name_utf8="slice_scalar";scalar.values=values.data();scalar.tuple_count=values.size();
        gx3de_scientific_polydata_spec create{};create.struct_size=sizeof(create);create.points=points.data();create.point_count=points.size();
        create.cells=cells.data();create.cell_count=cells.size();create.arrays=&scalar;create.array_count=1;
        rc=gx3de_scientific_create_polydata(scene,&create,out);if(rc!=GX3DE_OK)return rc;
        rc=gx3de_object_set_parent(*out,spec->field);
        if(rc!=GX3DE_OK){gx3de_object_destroy(*out);*out=nullptr;return rc;}
        gx3de_scientific_field_roles roles{};roles.struct_size=sizeof(roles);roles.scalar_array=0;
        roles.vector_array=-1;roles.radius_array=-1;
        rc=gx3de_scientific_field_roles_set(*out,&roles);
        if(rc!=GX3DE_OK){gx3de_object_destroy(*out);*out=nullptr;return rc;}
        gx3de_object_style style{};style.struct_size=sizeof(style);
        if(gx3de_object_style_get(*out,&style)==GX3DE_OK){style.scalar_coloring=1;
            rc=gx3de_object_style_set(*out,&style);if(rc!=GX3DE_OK){gx3de_object_destroy(*out);*out=nullptr;return rc;}}
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}

extern "C" GX3DE_API gx3de_result gx3de_field_pathlines_create(gx3de_scene* scene,
    const gx3de_field_pathline_spec* spec,gx3de_object** out,gx3de_field_pathline_info* info){
    if(!scene||!spec||!out||!info||spec->struct_size<sizeof(*spec)||info->struct_size<sizeof(*info))return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;gx3de_field_pathline_info result{};result.struct_size=sizeof(result);
    if(!spec->times||spec->frame_count<2||spec->frame_count>256||(!spec->frames&&!spec->loader)||
       !spec->seed_points||!spec->seed_count||spec->seed_count>10000||
       !std::isfinite(spec->time_step)||spec->time_step<=0||
       !std::isfinite(spec->min_vector_magnitude)||spec->min_vector_magnitude<=0||
       !std::isfinite(spec->tube_radius)||spec->tube_radius<0||
       spec->max_steps_per_seed<1||spec->max_steps_per_seed>100000||
       spec->max_output_points<2||spec->max_output_points>1000000||
       spec->max_memory_bytes<1024||spec->max_memory_bytes>512ull*1024*1024)return GX3DE_INVALID_ARGUMENT;
    for(uint64_t i=0;i<spec->frame_count;++i)if(!std::isfinite(spec->times[i])||
        (i&&spec->times[i]<=spec->times[i-1]))return GX3DE_INVALID_ARGUMENT;
    result.requested_seeds=spec->seed_count;
    for(uint64_t i=0;i<spec->seed_count;++i)if(!finite(spec->seed_points[i]))return GX3DE_INVALID_ARGUMENT;
    const bool scalar=spec->scalar_array>=0;
    struct Path {std::vector<V> points;std::vector<double> times,scalars;bool active=true;uint64_t steps=0;};
    try{
        std::vector<Path> paths(size_t(spec->seed_count));
        for(uint64_t i=0;i<spec->seed_count;++i){paths[i].points.push_back(spec->seed_points[i]);
            paths[i].times.push_back(spec->times[0]);}
        uint64_t output_count=spec->seed_count;
        Grid left,right;gx3de_mat4 field_pose{};bool have_pose=false;
        auto load=[&](uint64_t index,Grid& grid)->gx3de_result{
            if(gx3de_field_cancelled())return GX3DE_UNSUPPORTED;
            gx3de_object* temporary=nullptr;
            gx3de_object* field=spec->frames?const_cast<gx3de_object*>(spec->frames[index]):nullptr;
            if(!field){auto rc=spec->loader(scene,index,spec->times[index],spec->loader_user,&temporary);
                ++result.loaded_frames;
                if(rc!=GX3DE_OK){if(temporary)gx3de_object_destroy(temporary);return rc;}
                if(!temporary)return GX3DE_DEGENERATE;
                field=temporary;}
            if(gx3de_field_cancelled()){if(temporary)gx3de_object_destroy(temporary);return GX3DE_UNSUPPORTED;}
            gx3de_scene* owner=nullptr;auto owner_rc=gx3de_object_scene_get(field,&owner);
            if(owner_rc!=GX3DE_OK||owner!=scene){
                if(temporary&&owner==scene)gx3de_object_destroy(temporary);
                return owner_rc!=GX3DE_OK?owner_rc:GX3DE_WRONG_OWNER;}
            gx3de_mat4 pose{};auto rc=gx3de_object_world_transform_get(field,&pose);
            if(rc==GX3DE_OK){if(!have_pose){field_pose=pose;have_pose=true;}
                else for(int k=0;k<16;++k)if(std::abs(field_pose.m[k]-pose.m[k])>1e-12){rc=GX3DE_UNSUPPORTED;break;}}
            if(rc==GX3DE_OK)rc=read_path_grid(field,spec->vector_array,spec->scalar_array,
                spec->max_memory_bytes/2,grid);
            if(temporary)gx3de_object_destroy(temporary);
            return rc;
        };
        auto rc=load(0,left);if(rc!=GX3DE_OK)return rc;
        const uint64_t output_bytes=spec->max_output_points*128ull+spec->seed_count*256ull;
        const uint64_t grid_bytes=left.count*(scalar?32u:24u)+
            left.points.size()*sizeof(V)+left.cells.size()*sizeof(Grid::Cell);
        if(grid_bytes>spec->max_memory_bytes/2||output_bytes>spec->max_memory_bytes-2*grid_bytes)return GX3DE_RANGE;
        for(uint64_t frame=0;frame+1<spec->frame_count;++frame){
            if(gx3de_field_cancelled())return GX3DE_UNSUPPORTED;
            rc=load(frame+1,right);if(rc!=GX3DE_OK)return rc;
            if(!compatible(left,right))return GX3DE_UNSUPPORTED;
            if(frame==0&&scalar)for(auto& path:paths){V velocity{};double value=0;
                if(!sample_time(left,right,path.points.front(),0,velocity,&value)){
                    path.active=false;++result.boundary_stops;path.scalars.push_back(0);
                }else path.scalars.push_back(value);}
            const double t0=spec->times[frame],t1=spec->times[frame+1],duration=t1-t0;
            const double desired=std::ceil(duration/spec->time_step);
            if(!std::isfinite(desired)||desired>1000000)return GX3DE_RANGE;
            const uint64_t subdivisions=std::max<uint64_t>(1,uint64_t(desired));
            const double dt=duration/double(subdivisions);
            for(uint64_t step=0;step<subdivisions;++step){
                if(gx3de_field_cancelled())return GX3DE_UNSUPPORTED;
                const double a=double(step)/subdivisions,mid=double(step+.5)/subdivisions,b=double(step+1)/subdivisions;
                for(auto& path:paths){if(!path.active)continue;
                    if(gx3de_field_cancelled())return GX3DE_UNSUPPORTED;
                    if(path.steps>=spec->max_steps_per_seed){++result.step_limit_stops;path.active=false;continue;}
                    V p=path.points.back(),k1{},k2{},k3{},k4{};
                    auto slope=[&](V at,double alpha,V& k)->Stop{
                        if(!sample_time(left,right,at,alpha,k,nullptr))return Stop::boundary;
                        if(norm(k)<spec->min_vector_magnitude)return Stop::low;
                        return Stop::limit;};
                    Stop stop=slope(p,a,k1);
                    if(stop==Stop::limit)stop=slope(add(p,mul(k1,dt/2)),mid,k2);
                    if(stop==Stop::limit)stop=slope(add(p,mul(k2,dt/2)),mid,k3);
                    if(stop==Stop::limit)stop=slope(add(p,mul(k3,dt)),b,k4);
                    V next{};double sampled_scalar=0;
                    if(stop==Stop::limit){next=add(p,mul(add(add(k1,mul(k2,2)),add(mul(k3,2),k4)),dt/6));
                        V v{};if(!sample_time(left,right,next,b,v,scalar?&sampled_scalar:nullptr))stop=Stop::boundary;}
                    if(stop!=Stop::limit){if(stop==Stop::boundary)++result.boundary_stops;
                        else ++result.low_magnitude_stops;path.active=false;continue;}
                    if(output_count>=spec->max_output_points)return GX3DE_RANGE;
                    path.points.push_back(next);path.times.push_back(t0+dt*(step+1));
                    if(scalar)path.scalars.push_back(sampled_scalar);
                    ++output_count;++path.steps;
                }
            }
            left=std::move(right);right=Grid{};
        }
        std::vector<V> points;std::vector<double> times,values;std::vector<std::vector<uint64_t>> ids;
        points.reserve(size_t(output_count));times.reserve(size_t(output_count));if(scalar)values.reserve(size_t(output_count));
        for(auto& path:paths){if(path.points.size()<2)continue;
            std::vector<uint64_t> line;line.reserve(path.points.size());
            for(size_t i=0;i<path.points.size();++i){line.push_back(points.size());points.push_back(path.points[i]);
                times.push_back(path.times[i]);if(scalar)values.push_back(path.scalars[i]);}
            ids.push_back(std::move(line));++result.created_lines;
        }
        result.output_points=points.size();*info=result;if(ids.empty())return GX3DE_NOT_FOUND;
        std::vector<gx3de_scientific_cell_input> cells;cells.reserve(ids.size());
        for(auto& line:ids){gx3de_scientific_cell_input c{};c.struct_size=sizeof(c);
            c.type=GX3DE_SCI_CELL_POLYLINE;c.point_ids=line.data();c.point_count=line.size();cells.push_back(c);}
        gx3de_scientific_array_input arrays[2]{};
        uint64_t count=0;if(scalar){arrays[count].struct_size=sizeof(arrays[count]);arrays[count].association=GX3DE_SCI_ASSOC_POINT;
            arrays[count].components=1;arrays[count].name_utf8="field_scalar";arrays[count].values=values.data();
            arrays[count].tuple_count=values.size();++count;}
        arrays[count].struct_size=sizeof(arrays[count]);arrays[count].association=GX3DE_SCI_ASSOC_POINT;
        arrays[count].components=1;arrays[count].name_utf8="time_value";arrays[count].values=times.data();
        arrays[count].tuple_count=times.size();++count;
        gx3de_scientific_polydata_spec create{};create.struct_size=sizeof(create);create.points=points.data();create.point_count=points.size();
        create.cells=cells.data();create.cell_count=cells.size();create.arrays=arrays;create.array_count=count;
        rc=gx3de_scientific_create_polydata(scene,&create,out);if(rc!=GX3DE_OK)return rc;
        if(have_pose){rc=gx3de_object_set_transform(*out,&field_pose);
            if(rc!=GX3DE_OK){gx3de_object_destroy(*out);*out=nullptr;return rc;}}
        gx3de_scientific_field_roles roles{};roles.struct_size=sizeof(roles);roles.scalar_array=0;
        roles.vector_array=-1;roles.radius_array=-1;roles.tube_radius=spec->tube_radius;
        rc=gx3de_scientific_field_roles_set(*out,&roles);
        if(rc!=GX3DE_OK){gx3de_object_destroy(*out);*out=nullptr;return rc;}
        gx3de_object_style style{};style.struct_size=sizeof(style);
        if(gx3de_object_style_get(*out,&style)==GX3DE_OK){style.scalar_coloring=1;
            rc=gx3de_object_style_set(*out,&style);if(rc!=GX3DE_OK){gx3de_object_destroy(*out);*out=nullptr;return rc;}}
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
