/* SPDX-License-Identifier: GPL-3.0-or-later */
gx3de_result gx3de_compare_geometry(gx3de_object* reference,gx3de_object* target,
    const gx3de_geometry_comparison_spec* spec,gx3de_geometry_comparison* summary,
    gx3de_geometry_deviation* rows,uint64_t capacity,uint64_t* row_count) {
    if(!reference||!target||reference->scene!=target->scene||!spec||spec->struct_size<sizeof(*spec)||
       spec->sample_budget<6||spec->sample_budget>4096||!summary||summary->struct_size<sizeof(*summary)||
       !rows||!row_count||capacity<2ull*spec->sample_budget)return GX3DE_INVALID_ARGUMENT;
    if(spec->tessellation.struct_size<sizeof(spec->tessellation)||
       !std::isfinite(spec->tessellation.linear_deflection)||spec->tessellation.linear_deflection<=0||
       !std::isfinite(spec->tessellation.angular_deflection)||spec->tessellation.angular_deflection<=0||spec->tessellation.angular_deflection>std::acos(-1.0)||
       !std::isfinite(spec->tessellation.weld_tolerance)||spec->tessellation.weld_tolerance<=0||
       !spec->tessellation.max_triangles||spec->tessellation.max_triangles>10000000||
       !spec->tessellation.max_output_bytes||spec->tessellation.max_output_bytes>536870912)return GX3DE_INVALID_ARGUMENT;
    auto dispose=[](gx3de_object* value){if(value)gx3de_object_destroy(value);};
    std::unique_ptr<gx3de_object,decltype(dispose)> reference_cache(nullptr,dispose),target_cache(nullptr,dispose);
    gx3de_geometry_comparison result{};result.struct_size=sizeof(result);
    try {
        gx3de_object* sources[2]={reference,target};
        for(unsigned direction=0;direction<2;++direction) {
            if(!sources[direction]->mesh) {
                gx3de_object* generated=nullptr;
                auto code=gx3de_object_brep_mesh_create_world(sources[direction],&spec->tessellation,&generated);
                if(code!=GX3DE_OK)return code;
                (direction==0?reference_cache:target_cache).reset(generated);sources[direction]=generated;
                if(direction==0)result.reference_tessellated=1;else result.target_tessellated=1;
            }
            if(sources[direction]->mesh->vertices.empty()||sources[direction]->mesh->triangles.empty()||
               !spec->tessellation.max_triangles||sources[direction]->mesh->triangles.size()/3>spec->tessellation.max_triangles||
               sources[direction]->mesh->vertices.size()*sizeof(gx3de_vec3)+sources[direction]->mesh->triangles.size()*sizeof(uint32_t)>spec->tessellation.max_output_bytes)
                return GX3DE_RANGE;
        }
        std::vector<gx3de_vec3> vertices[2];std::vector<gx3de_geometry_deviation> output;
        output.reserve(2*spec->sample_budget);
        for(unsigned direction=0;direction<2;++direction) {
            auto matrix=world(sources[direction]);vertices[direction].reserve(sources[direction]->mesh->vertices.size());
            for(auto point:sources[direction]->mesh->vertices)vertices[direction].push_back(apply(matrix,point));
        }
        result.reference_vertices=vertices[0].size();result.target_vertices=vertices[1].size();
        long double total_squared=0,reference_squared=0,reference_sum=0;result.closest_sampled=std::numeric_limits<double>::infinity();
        for(unsigned direction=0;direction<2;++direction) {
            uint64_t count=std::min<uint64_t>(spec->sample_budget,vertices[direction].size());
            if(direction==0)result.reference_samples=count;else result.target_samples=count;
            std::vector<gx3de_vec3> queries;std::vector<uint64_t> indices;
            for(uint64_t i=0;i<count;++i) {uint64_t index=count==1?0:i*(vertices[direction].size()-1)/(count-1);indices.push_back(index);queries.push_back(vertices[direction][index]);}
            std::vector<double> distances;std::vector<gx3de_vec3> projected;std::string error;
            if(!gx3de_backend::vtk_surface_query_batch(vertices[1-direction],sources[1-direction]->mesh->triangles,queries,distances,projected,error))return GX3DE_DEGENERATE;
            for(size_t i=0;i<queries.size();++i) {
                double distance=distances[i];total_squared+=static_cast<long double>(distance)*distance;
                result.hausdorff_sampled=std::max(result.hausdorff_sampled,distance);
                if(direction==0){reference_squared+=static_cast<long double>(distance)*distance;reference_sum+=distance;result.reference_max=std::max(result.reference_max,distance);}
                if(distance<result.closest_sampled){result.closest_sampled=distance;result.closest_source=direction==0?queries[i]:projected[i];result.closest_target=direction==0?projected[i]:queries[i];}
                output.push_back({indices[i],direction,0,queries[i],projected[i],distance});
            }
        }
        result.reference_rms=std::sqrt(static_cast<double>(reference_squared/result.reference_samples));
        result.reference_mean=static_cast<double>(reference_sum/result.reference_samples);
        result.symmetric_rms=std::sqrt(static_cast<double>(total_squared/output.size()));
        double areas[2]={},volumes[2]={};uint32_t defined[2]={};
        for(unsigned direction=0;direction<2;++direction) {
            gx3de_mesh_diagnostics mesh{};mesh.struct_size=sizeof(mesh);
            gx3de_brep_diagnostics brep{};brep.struct_size=sizeof(brep);
            auto* original=direction==0?reference:target;
            auto code=original->mesh?gx3de_mesh_diagnose_world(original,&mesh):gx3de_brep_diagnose(original,&brep);
            if(code!=GX3DE_OK)return code;
            areas[direction]=original->mesh?mesh.surface_area:brep.surface_area;
            volumes[direction]=original->mesh?mesh.enclosed_volume:brep.enclosed_volume;
            defined[direction]=original->mesh?mesh.volume_defined:brep.volume_defined;
        }
        result.area_difference=areas[1]-areas[0];result.volume_defined=defined[0]&&defined[1];
        result.volume_difference=result.volume_defined?volumes[1]-volumes[0]:0;
        gx3de_bounds a{},b{};auto code=gx3de_object_bounds(reference,1,&a);if(code!=GX3DE_OK)return code;
        code=gx3de_object_bounds(target,1,&b);if(code!=GX3DE_OK)return code;
        result.bounds_min_difference=sub(b.min,a.min);result.bounds_max_difference=sub(b.max,a.max);
        std::copy(output.begin(),output.end(),rows);*row_count=output.size();*summary=result;return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
     catch(const std::exception&){return GX3DE_DEGENERATE;}
}
