// SPDX-License-Identifier: GPL-3.0-or-later
// Private VTK presentation of the immutable CORE object data. Included after
// the opaque-handle definitions in native_3d_engine_api_v1.cpp.
class gx3de_shadow_map_clear_pass final : public vtkRenderPass {
public:
    static gx3de_shadow_map_clear_pass* New(){return new gx3de_shadow_map_clear_pass;}
    vtkTypeMacro(gx3de_shadow_map_clear_pass,vtkRenderPass);
    vtkSmartPointer<vtkRenderPass> delegate;
    gx3de_render_viewport* viewport=nullptr;
    void Render(const vtkRenderState* state) override {
        // VTK 9.3 stores exp(11*z) in a floating-point shadow texture.
        // Its default zero color clear marks every uncovered texel shadowed.
        // Clear to the far-depth encoding before rendering each light map.
        const GLfloat far_depth[4]={static_cast<GLfloat>(std::exp(11.0)),0,0,1};
        glClearBufferfv(GL_COLOR,0,far_depth);
        glClear(GL_DEPTH_BUFFER_BIT);
        std::unordered_set<vtkProp*> excluded;
        if(viewport){
            for(const auto& actor:viewport->overlay_actors)excluded.insert(actor);
            for(const auto& prop:viewport->props)
                if(prop.object&&prop.geometry_kind&&
                   (!prop.object->casts_shadows||prop.object->opacity<=0.0||
                    (viewport->viewport->view->scene->engine->graphics.shadow_policy==GX3DE_SHADOW_OPAQUE_ONLY&&prop.object->opacity<1.0)))
                    excluded.insert(prop.actor);
            // Coplanar image decals are receivers, not separate casters.
            for(const auto& entry:viewport->texture_actors)excluded.insert(entry.first);
        }
        std::vector<vtkProp*> casters;
        for(int i=0;i<state->GetPropArrayCount();++i){auto* prop=state->GetPropArray()[i];
            if(!excluded.count(prop))casters.push_back(prop);}
        vtkRenderState filtered(state->GetRenderer());
        filtered.SetFrameBuffer(state->GetFrameBuffer());
        filtered.SetRequiredKeys(state->GetRequiredKeys());
        filtered.SetPropArrayAndCount(casters.data(),int(casters.size()));
        // vtkOpaquePass skips actors whose display opacity is below one. The
        // baker needs their geometry, while the public object opacity remains
        // available to the shadow shader for ordered coverage attenuation.
        std::vector<std::pair<vtkActor*,double>> restored;
        if(viewport)for(const auto& prop:viewport->props)
            if(prop.object&&prop.geometry_kind&&prop.object->casts_shadows&&
               prop.object->opacity>0.0&&prop.object->opacity<1.0&&
               viewport->viewport->view->scene->engine->graphics.shadow_policy==GX3DE_SHADOW_FULL&&
               !excluded.count(prop.actor)){
                auto* actor=prop.actor.GetPointer();
                restored.emplace_back(actor,actor->GetProperty()->GetOpacity());
                actor->GetProperty()->SetOpacity(1.0);
            }
        if(delegate){delegate->Render(&filtered);
            this->NumberOfRenderedProps=delegate->GetNumberOfRenderedProps();}
        for(const auto& entry:restored)
            entry.first->GetProperty()->SetOpacity(entry.second);
    }
    void ReleaseGraphicsResources(vtkWindow* window) override {
        if(delegate)delegate->ReleaseGraphicsResources(window);
    }
protected:
    gx3de_shadow_map_clear_pass()=default;
    ~gx3de_shadow_map_clear_pass() override=default;
};
class gx3de_shadow_baker_pass final : public vtkShadowMapBakerPass {
public:
    static gx3de_shadow_baker_pass* New(){return new gx3de_shadow_baker_pass;}
    vtkTypeMacro(gx3de_shadow_baker_pass,vtkShadowMapBakerPass);
    void SetViewport(gx3de_render_viewport* viewport){clear_pass->viewport=viewport;this->viewport=viewport;}
    void Render(const vtkRenderState* state) override {
        this->Superclass::Render(state);
        bool translucent=false;
        if(viewport)for(const auto& entry:viewport->props)
            if(entry.object&&entry.object->casts_shadows&&
               entry.object->opacity>0.0&&entry.object->opacity<1.0&&
               viewport->viewport->view->scene->engine->graphics.shadow_policy==GX3DE_SHADOW_FULL){
                translucent=true;break;}
        if(auto* maps=this->GetShadowMaps())for(auto& map:*maps)if(map){
            map->SetMagnificationFilter(translucent?vtkTextureObject::Nearest:
                vtkTextureObject::Linear);
            map->SetMinificationFilter(translucent?vtkTextureObject::Nearest:
                vtkTextureObject::Linear);
        }
    }
    bool PreReplaceShaderValues(std::string& vertex,std::string& geometry,
        std::string& fragment,vtkAbstractMapper* mapper,vtkProp* prop) override {
        const bool result=this->Superclass::PreReplaceShaderValues(
            vertex,geometry,fragment,mapper,prop);
        if(!result||!viewport||!prop||
           viewport->viewport->view->scene->engine->graphics.shadow_policy!=GX3DE_SHADOW_FULL)return result;
        size_t translucent_ordinal=0;
        for(size_t index=0;index<viewport->props.size();++index){
            const auto& entry=viewport->props[index];
            const bool translucent_entry=viewport->viewport->view->scene->engine->graphics.shadow_policy==
                GX3DE_SHADOW_FULL&&entry.object&&entry.object->casts_shadows&&
                entry.object->opacity>0.0&&entry.object->opacity<1.0;
            if(entry.actor.GetPointer()!=prop||!entry.object||
               !entry.object->casts_shadows){
                if(translucent_entry)++translucent_ordinal;
                continue;
            }
            const double opacity=entry.object->opacity;
            if(opacity<=0.0||opacity>=1.0)break;
            // A deterministic 4x4 ordered mask makes the fraction of shadow
            // map texels that survive approximately equal to object opacity.
            // Distinct rank shifts let overlapping translucent casters accumulate
            // coverage instead of sharing exactly the same holes.
            static const int bayer[16]={0,8,2,10,12,4,14,6,
                                        3,11,1,9,15,7,13,5};
            std::string code="int gx3de_bayer[16] = int[16](";
            for(int i=0;i<16;++i){if(i)code+=",";code+=std::to_string(bayer[i]);}
            code+=");\n";
            code+="int gx3de_bx=int(gl_FragCoord.x) & 3;\n";
            code+="int gx3de_by=int(gl_FragCoord.y) & 3;\n";
            code+="int gx3de_rank=(gx3de_bayer[gx3de_by*4+gx3de_bx]+"+
                std::to_string((translucent_ordinal*4)%16)+") & 15;\n";
            code+="if ((float(gx3de_rank)+0.5)/16.0 >= "+
                std::to_string(opacity)+") discard;\n";
            vtkShaderProgram::Substitute(fragment,"//VTK::Light::Impl",
                code+"//VTK::Light::Impl",false);
            break;
        }
        return result;
    }
protected:
    gx3de_shadow_baker_pass(){
        this->SetResolution(2048);
        if(auto* camera=vtkCameraPass::SafeDownCast(this->GetOpaqueSequence())){
            clear_pass=vtkSmartPointer<gx3de_shadow_map_clear_pass>::New();
            clear_pass->delegate=camera->GetDelegatePass();
            camera->SetDelegatePass(clear_pass);
        }
    }
    ~gx3de_shadow_baker_pass() override=default;
private:
    gx3de_render_viewport* viewport=nullptr;
    vtkSmartPointer<gx3de_shadow_map_clear_pass> clear_pass;
};
class gx3de_translucent_shadow_pass final : public vtkShadowMapPass {
public:
    static gx3de_translucent_shadow_pass* New(){return new gx3de_translucent_shadow_pass;}
    vtkTypeMacro(gx3de_translucent_shadow_pass,vtkShadowMapPass);
    gx3de_render_viewport* viewport=nullptr;
    bool PostReplaceShaderValues(std::string& vertex,std::string& geometry,
        std::string& fragment,vtkAbstractMapper* mapper,vtkProp* prop) override {
        const bool result=this->Superclass::PostReplaceShaderValues(
            vertex,geometry,fragment,mapper,prop);
        if(!result||!viewport||
           viewport->viewport->view->scene->engine->graphics.shadow_policy!=GX3DE_SHADOW_FULL)return result;
        bool translucent=false;
        for(const auto& entry:viewport->props)
            if(entry.object&&entry.object->casts_shadows&&
               entry.object->opacity>0.0&&entry.object->opacity<1.0&&
               viewport->viewport->view->scene->engine->graphics.shadow_policy==GX3DE_SHADOW_FULL){
                translucent=true;break;}
        if(!translucent)return result;
        const std::string old=
            "float depthCExpBlured = texture2D(shadowMap,projected).r;\n"
            "      expFactor = depthCExpBlured * depthCExpActual;";
        const std::string replacement=
            "ivec2 gx3de_size=textureSize(shadowMap,0);\n"
            "      ivec2 gx3de_base=clamp(ivec2(projected*vec2(gx3de_size)),"
            "ivec2(0),gx3de_size-ivec2(1));\n"
            "      float depthCExpBlured=texelFetch(shadowMap,gx3de_base,0).r;\n"
            "      float gx3de_sum=0.0;\n"
            "      for(int gx3de_y=0;gx3de_y<4;++gx3de_y)\n"
            "        for(int gx3de_x=0;gx3de_x<4;++gx3de_x){\n"
            "          ivec2 gx3de_p=clamp(gx3de_base+ivec2(gx3de_x-1,gx3de_y-1),"
            "ivec2(0),gx3de_size-ivec2(1));\n"
            "          float gx3de_exp=texelFetch(shadowMap,gx3de_p,0).r"
            "*depthCExpActual;\n"
            "          gx3de_sum+=min(1.0,gx3de_exp);\n"
            "        }\n"
            "      expFactor=gx3de_sum/16.0;";
        const auto position=fragment.find(old);
        if(position!=std::string::npos)fragment.replace(position,old.size(),replacement);
        else return false; // Refuse a VTK shader variant we cannot attenuate.
        return result;
    }
protected:
    gx3de_translucent_shadow_pass()=default;
    ~gx3de_translucent_shadow_pass() override=default;
};
class gx3de_shadow_opaque_sequence final : public vtkRenderPass {
public:
    static gx3de_shadow_opaque_sequence* New(){return new gx3de_shadow_opaque_sequence;}
    vtkTypeMacro(gx3de_shadow_opaque_sequence,vtkRenderPass);
    gx3de_render_viewport* viewport=nullptr;
    vtkShadowMapPass* shadow=nullptr;
    void Render(const vtkRenderState* state) override {
        // The stock VTK shadow pass marks every prop as a receiver. Remove its
        // shader key only for nonreceivers and editor overlays while its
        // ordinary lights/opaque sequence runs, then restore the key for VTK.
        std::vector<vtkActor*> exempt;
        auto exclude=[&](vtkActor* actor){
            auto* info=actor->GetPropertyKeys();
            if(info){info->Remove(vtkOpenGLRenderPass::RenderPasses(),shadow);
                exempt.push_back(actor);}
        };
        if(viewport){
            for(auto& actor:viewport->overlay_actors)exclude(actor);
            for(const auto& prop:viewport->props)
                if(prop.object&&prop.geometry_kind&&!prop.object->receives_shadows)
                    exclude(prop.actor);
            for(const auto& entry:viewport->texture_actors)
                if(!entry.second->receives_shadows)exclude(entry.first);
        }
        vtkNew<vtkLightsPass> lights;lights->Render(state);
        vtkNew<vtkOpaquePass> opaque;opaque->Render(state);
        this->NumberOfRenderedProps=opaque->GetNumberOfRenderedProps();
        for(auto* actor:exempt){auto* info=actor->GetPropertyKeys();
            if(info)info->Append(vtkOpenGLRenderPass::RenderPasses(),shadow);}
    }
protected:
    gx3de_shadow_opaque_sequence()=default;
    ~gx3de_shadow_opaque_sequence() override=default;
};
class gx3de_shadow_renderer final : public vtkOpenGLRenderer {
public:
    static gx3de_shadow_renderer* New(){return new gx3de_shadow_renderer;}
    vtkTypeMacro(gx3de_shadow_renderer,vtkOpenGLRenderer);
    void DeviceRender() override {
        this->Superclass::DeviceRender();
        // VTK 9.3's UseShadows branch omits its normal translucent stage.
        // Render transparent actors after the opaque shadow pass. Their
        // shadow-map coverage is handled separately by the baker above.
        if(this->GetUseShadows())this->DeviceRenderTranslucentPolygonalGeometry();
    }
    void Configure(gx3de_render_viewport* viewport){
        vtkNew<gx3de_shadow_baker_pass> baker;baker->SetViewport(viewport);
        if(viewport->viewport->view->scene->scientific_lights.size()>4)
            baker->SetResolution(1024);
        vtkNew<gx3de_translucent_shadow_pass> shadow;
        vtkNew<gx3de_shadow_opaque_sequence> opaque;
        opaque->viewport=viewport;opaque->shadow=shadow;
        shadow->viewport=viewport;
        shadow->SetShadowMapBakerPass(baker);
        shadow->SetOpaqueSequence(opaque);
        if(this->ShadowMapPass)this->ShadowMapPass->Delete();
        this->ShadowMapPass=shadow;this->ShadowMapPass->Register(this);
        this->UseShadowsOn();
    }
protected:
    gx3de_shadow_renderer()=default;
    ~gx3de_shadow_renderer() override=default;
};
static vtkSmartPointer<vtkPolyData> renderer_mesh_poly(const Mesh& mesh,bool smooth=false) {
    vtkNew<vtkPoints> points;points->SetDataTypeToDouble();
    points->SetNumberOfPoints(static_cast<vtkIdType>(mesh.vertices.size()));
    for(size_t i=0;i<mesh.vertices.size();++i){const auto& p=mesh.vertices[i];
        points->SetPoint(static_cast<vtkIdType>(i),p.x,p.y,p.z);}
    vtkNew<vtkCellArray> faces;
    for(size_t i=0;i<mesh.triangles.size();i+=3){vtkIdType ids[3]={
        static_cast<vtkIdType>(mesh.triangles[i]),static_cast<vtkIdType>(mesh.triangles[i+1]),
        static_cast<vtkIdType>(mesh.triangles[i+2])};faces->InsertNextCell(3,ids);}
    auto poly=vtkSmartPointer<vtkPolyData>::New();poly->SetPoints(points);poly->SetPolys(faces);
    if(smooth){
        vtkNew<vtkPolyDataNormals> normals;
        normals->SetInputData(poly);
        normals->ComputePointNormalsOn();
        normals->ComputeCellNormalsOff();
        normals->SplittingOn();
        normals->SetFeatureAngle(60.0);
        normals->ConsistencyOn();
        normals->Update();
        poly->ShallowCopy(normals->GetOutput());
    }
    return poly;
}

static const Mesh* renderer_display_mesh(gx3de_target* target,const gx3de_object* object,
                                         std::string& error) {
    const auto& policy=target->engine->graphics;
    const uint32_t level=target->interaction_active&&policy.interaction_lod_enabled?
        policy.interaction_lod:policy.normal_lod;
    if(level==GX3DE_LOD_FULL||object->mesh->triangles.size()<300)return object->mesh.get();
    const std::string key=object->fingerprint+":"+
        std::to_string(reinterpret_cast<uintptr_t>(object->mesh.get()))+":"+std::to_string(level);
    auto found=target->display_lod_cache.find(key);
    if(found!=target->display_lod_cache.end())return found->second.get();
    Mesh derived;
    /* A sparse progressive preview can have valid faces yet be unsuitable
     * for quadric reduction. Keep its source geometry visible; the normal
     * display triangle and GPU budgets still apply to that fallback. */
    if(!gx3de_backend::mesh_lod(*object->mesh,level,derived,error))
        return object->mesh.get();
    if(target->display_lod_cache.size()>=64)target->display_lod_cache.clear();
    auto stored=std::make_shared<const Mesh>(std::move(derived));
    target->display_lod_cache.emplace(key,stored);
    return stored.get();
}
#ifdef GX3DE_WITH_OCCT
static const Mesh* renderer_brep_display_mesh(gx3de_target* target,const gx3de_object* object,
                                              std::string& error) {
    const auto& policy=target->engine->graphics;
    const uint32_t level=target->interaction_active&&policy.interaction_lod_enabled?
        policy.interaction_lod:policy.normal_lod;
    const std::string key="brep:"+std::to_string(reinterpret_cast<uintptr_t>(object->brep.get()))+
        ":"+std::to_string(level);
    auto found=target->display_lod_cache.find(key);
    if(found!=target->display_lod_cache.end())return found->second.get();
    const double linear[]={0,0.7,0.5,0.25,0.1,0.05};
    const double angular[]={0,1.2,1.0,0.8,0.6,0.4};
    const uint64_t triangles[]={0,100000,250000,500000,1000000,2000000};
    Mesh mesh;
    if(!gx3de_backend::tessellate_brep(*object->brep,linear[level],angular[level],1e-9,
        triangles[level],256ull*1024*1024,mesh,error))return nullptr;
    if(target->display_lod_cache.size()>=64)target->display_lod_cache.clear();
    auto stored=std::make_shared<const Mesh>(std::move(mesh));
    target->display_lod_cache.emplace(key,stored);
    return stored.get();
}
#endif

static vtkSmartPointer<vtkMatrix4x4> renderer_matrix(const gx3de_mat4& pose) {
    auto matrix=vtkSmartPointer<vtkMatrix4x4>::New();
    for(int row=0;row<4;++row)for(int col=0;col<4;++col)
        matrix->SetElement(row,col,pose.m[col*4+row]);
    return matrix;
}

static vtkSmartPointer<vtkLookupTable> renderer_lut(const gx3de_scientific_presentation& p) {
    auto lut=vtkSmartPointer<vtkLookupTable>::New();lut->SetNumberOfTableValues(256);
    constexpr double viridis[][3]={{0.267,0.005,0.329},{0.283,0.141,0.458},
        {0.254,0.265,0.530},{0.207,0.372,0.553},{0.164,0.471,0.558},
        {0.128,0.567,0.551},{0.267,0.749,0.441},{0.478,0.821,0.318},
        {0.741,0.873,0.150},{0.993,0.906,0.144}};
    constexpr double coolwarm[][3]={{0.230,0.299,0.754},{0.554,0.690,0.996},
        {0.865,0.865,0.865},{0.956,0.598,0.477},{0.706,0.016,0.150}};
    for(int i=0;i<256;++i){const double t=double(i)/255.0;double rgb[3]{};
        if(p.colormap==GX3DE_COLORMAP_GRAYSCALE){rgb[0]=rgb[1]=rgb[2]=t;}
        else {const double (*stops)[3]=p.colormap==GX3DE_COLORMAP_COOL_WARM?coolwarm:viridis;
            const int n=p.colormap==GX3DE_COLORMAP_COOL_WARM?5:10;
            const double index=t*(n-1);const int lo=std::min(n-2,int(index));const double f=index-lo;
            for(int j=0;j<3;++j)rgb[j]=stops[lo][j]*(1-f)+stops[lo+1][j]*f;}
        lut->SetTableValue(i,rgb[0],rgb[1],rgb[2],1.0);}
    lut->Build();return lut;
}
static bool renderer_valid_rgb(gx3de_rgb c) {
    return std::isfinite(c.r)&&std::isfinite(c.g)&&std::isfinite(c.b)&&
           c.r>=0&&c.r<=1&&c.g>=0&&c.g<=1&&c.b>=0&&c.b<=1;
}

static void renderer_apply_clips(vtkAbstractMapper* mapper,const gx3de_view* view) {
    for(const auto& c:view->clips)if(c.enabled){vtkNew<vtkPlane> plane;
        plane->SetOrigin(c.origin.x,c.origin.y,c.origin.z);
        const double sign=c.keep_positive?1.0:-1.0;
        plane->SetNormal(sign*c.normal.x,sign*c.normal.y,sign*c.normal.z);
        mapper->AddClippingPlane(plane);}
    if(view->clip_box.enabled){const auto& b=view->clip_box.world_bounds;
        const gx3de_vec3 origins[6]={{b.min.x,0,0},{b.max.x,0,0},
            {0,b.min.y,0},{0,b.max.y,0},{0,0,b.min.z},{0,0,b.max.z}};
        const gx3de_vec3 normals[6]={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
        for(int i=0;i<6;++i){vtkNew<vtkPlane> plane;
            plane->SetOrigin(origins[i].x,origins[i].y,origins[i].z);
            plane->SetNormal(normals[i].x,normals[i].y,normals[i].z);
            mapper->AddClippingPlane(plane);}}
}
static void renderer_apply_style(vtkActor* actor,const gx3de_object* object,
                                 const gx3de_view* view) {
    const auto& s=object->style;auto* property=actor->GetProperty();
    property->SetColor(s.color.r,s.color.g,s.color.b);
    property->SetLineWidth(s.line_width);property->SetPointSize(s.point_size);
    property->SetBackfaceCulling(s.backface_culling);
    if(s.mode==GX3DE_DISPLAY_WIREFRAME)property->SetRepresentationToWireframe();
    else if(s.mode==GX3DE_DISPLAY_POINTS)property->SetRepresentationToPoints();
    else {property->SetRepresentationToSurface();
        property->SetEdgeVisibility(s.mode==GX3DE_DISPLAY_SURFACE_EDGES);}
    property->SetOpacity(object->opacity);
    bool scientific_lighting=false;
    for(const auto* light:view->scene->scientific_lights)
        if(light->spec.enabled){scientific_lighting=true;break;}
    if(view->lighting.enabled||scientific_lighting){property->LightingOn();
        property->SetAmbient(view->lighting.ambient);
        property->SetDiffuse(view->lighting.diffuse);
        property->SetSpecular(view->lighting.specular);
        property->SetSpecularPower(24);}
    else property->LightingOff();
}

static void renderer_add_prop(gx3de_render_viewport& rv,gx3de_object* object,
    uint32_t kind,vtkPolyData* poly,const gx3de_mat4& pose,const gx3de_view* view,
    bool scalar=false,uint32_t association=0,int array_index=-1,vtkDataArray* array=nullptr,
    bool direct_rgba=false,bool translucent_rgba=false) {
    if(!poly||poly->GetNumberOfPoints()==0)return;
    vtkNew<vtkPolyDataMapper> mapper;mapper->SetInputData(poly);
    if(direct_rgba){if(poly->GetCellData()->GetArray("__gx3de_display_rgba"))mapper->SetScalarModeToUseCellFieldData();else mapper->SetScalarModeToUsePointFieldData();
        mapper->SelectColorArray("__gx3de_display_rgba");
        mapper->SetColorModeToDirectScalars();mapper->ScalarVisibilityOn();}
    else if(scalar&&array&&object->style.scalar_coloring){if(association==GX3DE_SCI_ASSOC_CELL)mapper->SetScalarModeToUseCellFieldData();
        else mapper->SetScalarModeToUsePointFieldData();
        if(array->GetName()&&array->GetName()[0])mapper->SelectColorArray(array->GetName());
        else mapper->SelectColorArray(array_index);
        mapper->SetColorModeToMapScalars();mapper->SetLookupTable(renderer_lut(object->presentation));
        double range[2];array->GetRange(range);
        if(object->presentation.use_scalar_range){range[0]=object->presentation.scalar_min;
            range[1]=object->presentation.scalar_max;}
        if(range[0]==range[1])range[1]=range[0]+1;
        mapper->SetScalarRange(range);mapper->ScalarVisibilityOn();
    }else mapper->ScalarVisibilityOff();
    renderer_apply_clips(mapper,view);
    vtkNew<vtkActor> actor;actor->SetMapper(mapper);actor->SetUserMatrix(renderer_matrix(pose));
    renderer_apply_style(actor,object,view);
    if(direct_rgba){actor->GetProperty()->SetOpacity(1.0);
        if(translucent_rgba)actor->ForceTranslucentOn();}
    if(poly->GetPointData()->GetNormals())actor->GetProperty()->SetInterpolationToPhong();
    rv.renderer->AddActor(actor);rv.props.push_back({actor,object,kind,pose});
}

/* Opaque closed particle geometry uses the normal depth, lighting and shadow
 * passes. No transmission model or synthetic shadow is applied. */
static vtkPolyData* renderer_cloud_geometry(gx3de_particle_cloud* cloud){
    if(cloud->geometry)return cloud->geometry;
    static constexpr double phi=1.618033988749895;
    static const double vertices[12][3]={
        {-1,phi,0},{1,phi,0},{-1,-phi,0},{1,-phi,0},
        {0,-1,phi},{0,1,phi},{0,-1,-phi},{0,1,-phi},
        {phi,0,-1},{phi,0,1},{-phi,0,-1},{-phi,0,1}};
    static const int faces[20][3]={
        {0,11,5},{0,5,1},{0,1,7},{0,7,10},{0,10,11},
        {1,5,9},{5,11,4},{11,10,2},{10,7,6},{7,1,8},
        {3,9,4},{3,4,2},{3,2,6},{3,6,8},{3,8,9},
        {4,9,5},{2,4,11},{6,2,10},{8,6,7},{9,8,1}};
    vtkNew<vtkPoints> points;vtkNew<vtkCellArray> polys;
    vtkNew<vtkFloatArray> normals;normals->SetNumberOfComponents(3);
    vtkNew<vtkUnsignedCharArray> colors;colors->SetNumberOfComponents(3);
    colors->SetName("particle_rgb");
    points->Allocate(static_cast<vtkIdType>(cloud->particles.size()*12));
    for(const auto& particle:cloud->particles){
        const double radius=(particle.flags&GX3DE_PARTICLE_RADIUS)?particle.radius:cloud->style.radius;
        const auto color=(particle.flags&GX3DE_PARTICLE_COLOR)?particle.color:cloud->style.color;
        const unsigned char rgb[3]={static_cast<unsigned char>(std::lround(color.r*255)),
            static_cast<unsigned char>(std::lround(color.g*255)),
            static_cast<unsigned char>(std::lround(color.b*255))};
        const vtkIdType base=points->GetNumberOfPoints();
        for(const auto& vertex:vertices){
            const double inv=1.0/std::sqrt(vertex[0]*vertex[0]+vertex[1]*vertex[1]+vertex[2]*vertex[2]);
            const float normal[3]={float(vertex[0]*inv),float(vertex[1]*inv),float(vertex[2]*inv)};
            points->InsertNextPoint(particle.position.x+radius*normal[0],
                particle.position.y+radius*normal[1],particle.position.z+radius*normal[2]);
            normals->InsertNextTypedTuple(normal);colors->InsertNextTypedTuple(rgb);
        }
        for(const auto& face:faces){const vtkIdType ids[3]={base+face[0],base+face[1],base+face[2]};
            polys->InsertNextCell(3,ids);}
    }
    vtkNew<vtkPolyData> poly;poly->SetPoints(points);poly->SetPolys(polys);
    poly->GetPointData()->SetNormals(normals);poly->GetPointData()->SetScalars(colors);
    cloud->geometry=poly;return cloud->geometry;
}
static void renderer_add_cloud(gx3de_render_viewport& rv,gx3de_particle_cloud* cloud){
    if(!cloud->visible||cloud->style.opacity<=0||cloud->particles.empty())return;
    vtkNew<vtkPolyDataMapper> mapper;mapper->SetInputData(renderer_cloud_geometry(cloud));
    mapper->SetColorModeToDirectScalars();mapper->SetScalarModeToUsePointData();
    mapper->ScalarVisibilityOn();renderer_apply_clips(mapper,rv.viewport->view);
    vtkNew<vtkActor> actor;actor->SetMapper(mapper);
    actor->SetUserMatrix(renderer_matrix(cloud->transform));
    auto* property=actor->GetProperty();property->SetOpacity(cloud->style.opacity);
    const auto& lighting=rv.viewport->view->lighting;
    bool scientific_lighting=false;
    for(const auto* light:rv.viewport->view->scene->scientific_lights)
        if(light->spec.enabled){scientific_lighting=true;break;}
    if(lighting.enabled||scientific_lighting){property->LightingOn();property->SetAmbient(lighting.ambient);
        property->SetDiffuse(lighting.diffuse);property->SetSpecular(lighting.specular);
        property->SetSpecularPower(22);property->SetInterpolationToPhong();}
    else property->LightingOff();
    rv.renderer->AddActor(actor);rv.props.push_back({actor,nullptr,0,cloud->transform});
}

/* Evidence geometry follows the scientific centerline state. Translucent,
 * nonpickable tubes are visual aids and do not enter the shadow-map baker. */
static void renderer_add_scientific_beams(gx3de_render_viewport& rv){
    for(const auto* light:rv.viewport->view->scene->scientific_lights){
        const auto& s=light->spec;if(!s.enabled||!s.beam_visible||s.intensity<=0)continue;
        const auto spectral=scientific_light_rgb(s.wavelength_nm);
        if(spectral.r+spectral.g+spectral.b<=0)continue;
        auto add_segment=[&](double start,double end,double optical){
            if(end-start<=1e-6||optical<=0)return;
            const auto a=add(s.position,mul(s.direction,start));
            const auto b=add(s.position,mul(s.direction,end));
            vtkNew<vtkPoints> points;points->InsertNextPoint(a.x,a.y,a.z);
            points->InsertNextPoint(b.x,b.y,b.z);
            vtkNew<vtkCellArray> lines;vtkIdType ids[2]={0,1};lines->InsertNextCell(2,ids);
            vtkNew<vtkPolyData> line;line->SetPoints(points);line->SetLines(lines);
            vtkNew<vtkTubeFilter> tube;tube->SetInputData(line);
            tube->SetRadius(s.beam_radius);tube->SetNumberOfSides(7);tube->CappingOn();
            vtkNew<vtkPolyDataMapper> mapper;mapper->SetInputConnection(tube->GetOutputPort());
            vtkNew<vtkActor> actor;actor->SetMapper(mapper);actor->PickableOff();
            actor->GetProperty()->LightingOff();
            const double brightness=std::clamp(optical,0.0,1.0);
            actor->GetProperty()->SetColor(spectral.r*brightness,spectral.g*brightness,
                                            spectral.b*brightness);
            actor->GetProperty()->SetOpacity(.72);actor->ForceTranslucentOn();
            rv.renderer->AddActor(actor);
        };
        double start=0,optical=1;
        for(const auto& exit:scientific_beam_exits(light)){
            add_segment(start,exit.distance,optical);
            start=exit.distance;optical*=exit.transmittance;
        }
        add_segment(start,s.beam_range,optical);
        vtkNew<vtkSphereSource> sphere;sphere->SetCenter(s.position.x,s.position.y,s.position.z);
        sphere->SetRadius(std::max(s.beam_radius*2.4,.045));sphere->SetThetaResolution(12);
        sphere->SetPhiResolution(8);
        vtkNew<vtkPolyDataMapper> mapper;mapper->SetInputConnection(sphere->GetOutputPort());
        vtkNew<vtkActor> actor;actor->SetMapper(mapper);actor->PickableOff();
        actor->GetProperty()->LightingOff();actor->GetProperty()->SetColor(spectral.r,spectral.g,spectral.b);
        actor->GetProperty()->SetOpacity(.78);actor->ForceTranslucentOn();rv.renderer->AddActor(actor);
    }
}

static void renderer_add_planar_textures(gx3de_render_viewport& rv,gx3de_object* object,
                                         const gx3de_mat4& pose,const gx3de_view* view) {
    auto add_texture=[&](vtkPolyData* patch,vtkImageData* pixels){
        vtkNew<vtkPolyDataMapper> mapper;mapper->SetInputData(patch);
        mapper->ScalarVisibilityOff();renderer_apply_clips(mapper,view);
        vtkNew<vtkTexture> texture;texture->SetInputData(pixels);
        texture->InterpolateOn();texture->RepeatOff();texture->EdgeClampOn();
        vtkNew<vtkActor> actor;actor->SetMapper(mapper);
        actor->SetUserMatrix(renderer_matrix(pose));
        renderer_apply_style(actor,object,view);
        actor->GetProperty()->SetColor(1.0,1.0,1.0);
        actor->GetProperty()->SetRepresentationToSurface();
        actor->GetProperty()->SetEdgeVisibility(false);
        actor->GetProperty()->SetInterpolationToPhong();
        actor->SetTexture(texture);actor->PickableOff();
        // The renderer owns this static scene actor until the static state is
        // rebuilt. Camera-only reuse clears overlay_actors, so a texture must
        // never be registered there.
        rv.renderer->AddActor(actor);
        rv.texture_actors.emplace_back(actor,object);
    };
    for(const auto* assignment:object->planar_textures)
        add_texture(assignment->patch,assignment->image->pixels);
    for(const auto* assignment:object->curved_textures)
        add_texture(assignment->patch,assignment->image->pixels);
}

static gx3de_result renderer_add_scientific(gx3de_render_viewport& rv,gx3de_object* object,
    uint64_t& displayed_triangles,uint64_t display_budget) {
    auto* data=object->scientific->dataset.GetPointer();if(!data)return GX3DE_DEGENERATE;
    if(object->volume_style.enabled){
        auto* image=vtkImageData::SafeDownCast(data);
        if(!image||data->GetNumberOfPoints()>4000000)return GX3DE_RANGE;
        uint32_t association=0;
        auto* scalar=scientific_array_by_index(*object->scientific,
            object->volume_style.scalar_array,&association);
        if(!scalar||association!=GX3DE_SCI_ASSOC_POINT||
           scalar->GetNumberOfComponents()!=1||!scalar->GetName())return GX3DE_DEGENERATE;
        vtkNew<vtkSmartVolumeMapper> mapper;mapper->SetInputData(image);
        mapper->SetRequestedRenderModeToDefault();
        mapper->SetScalarModeToUsePointFieldData();
        mapper->SelectScalarArray(scalar->GetName());
        mapper->SetAutoAdjustSampleDistances(0);
        mapper->SetInteractiveAdjustSampleDistances(0);
        mapper->SetSampleDistance(static_cast<float>(object->volume_style.sample_distance));
        renderer_apply_clips(mapper,rv.viewport->view);
        vtkNew<vtkColorTransferFunction> colors;
        vtkNew<vtkPiecewiseFunction> opacity;
        for(uint32_t i=0;i<object->volume_style.transfer_count;++i){
            const auto& p=object->volume_style.transfer[i];
            colors->AddRGBPoint(p.scalar,p.red,p.green,p.blue);
            opacity->AddPoint(p.scalar,p.opacity*object->opacity);
        }
        vtkNew<vtkVolumeProperty> property;property->SetColor(colors);
        property->SetScalarOpacity(opacity);property->SetInterpolationTypeToLinear();
        property->SetShade(rv.viewport->view->lighting.enabled!=0);
        vtkNew<vtkVolume> volume;volume->SetMapper(mapper);volume->SetProperty(property);
        volume->SetUserMatrix(renderer_matrix(world(object)));
        rv.renderer->AddVolume(volume);
        rv.volumes.emplace_back(volume,object);
        return GX3DE_OK;
    }
    if(data->GetNumberOfPoints()>1000000||data->GetNumberOfCells()>1000000)return GX3DE_RANGE;
    if(auto* grid=vtkUnstructuredGrid::SafeDownCast(data)){
        uint64_t worst_case_faces=0;
        for(vtkIdType i=0;i<grid->GetNumberOfCells();++i){const int kind=grid->GetCellType(i);
            worst_case_faces+=kind==VTK_HEXAHEDRON?6u:kind==VTK_TETRA?4u:1u;
            if(worst_case_faces>4000000)return GX3DE_RANGE;}}
    vtkSmartPointer<vtkPolyData> poly;
    if(auto* p=vtkPolyData::SafeDownCast(data)){poly=p;}
    else {vtkNew<vtkGeometryFilter> geometry;geometry->SetInputData(data);geometry->Update();
        poly=vtkSmartPointer<vtkPolyData>::New();poly->ShallowCopy(geometry->GetOutput());}
    if(poly->GetNumberOfCells()>4000000||poly->GetNumberOfPoints()>4000000)
        return GX3DE_RANGE;
    if(poly->GetNumberOfCells()==0&&poly->GetNumberOfPoints()>0){vtkNew<vtkVertexGlyphFilter> glyph;
        glyph->SetInputData(poly);glyph->Update();auto pts=vtkSmartPointer<vtkPolyData>::New();
        pts->ShallowCopy(glyph->GetOutput());poly=pts;}
    auto roles=object->field_roles;
    vtkDataArray* scalar=nullptr;uint32_t scalar_assoc=0;int array_id=-1;
    if(roles.scalar_array>=0){scalar=scientific_array_by_index(*object->scientific,
        static_cast<uint64_t>(roles.scalar_array),&scalar_assoc);
        if(scalar){vtkFieldData* fd=scalar_assoc==GX3DE_SCI_ASSOC_POINT?
            static_cast<vtkFieldData*>(data->GetPointData()):static_cast<vtkFieldData*>(data->GetCellData());
            for(int i=0;i<fd->GetNumberOfArrays();++i)if(fd->GetArray(i)==scalar){array_id=i;break;}}}
    if(roles.tube_radius>0&&poly->GetLines()&&poly->GetLines()->GetNumberOfCells()>0){
        if(poly->GetLines()->GetNumberOfCells()>100000)return GX3DE_RANGE;
        vtkIdType line_points=0;poly->GetLines()->InitTraversal();vtkIdType count=0;
        const vtkIdType* ids=nullptr;
        while(poly->GetLines()->GetNextCell(count,ids)){
            line_points+=count;if(line_points>150000)return GX3DE_RANGE;}
        vtkNew<vtkTubeFilter> tube;tube->SetInputData(poly);tube->SetRadius(roles.tube_radius);
        tube->SetNumberOfSides(12);tube->CappingOn();tube->Update();
        auto tube_poly=vtkSmartPointer<vtkPolyData>::New();tube_poly->ShallowCopy(tube->GetOutput());poly=tube_poly;
        if(poly->GetNumberOfCells()>4000000)return GX3DE_RANGE;
    }
    bool direct_rgba=false,translucent_rgba=false;
    if(object->color_array>=0||object->opacity_array>=0){
        uint32_t direct_assoc=GX3DE_SCI_ASSOC_POINT;
        if(object->color_array>=0)scientific_array_by_index(*object->scientific,static_cast<uint64_t>(object->color_array),&direct_assoc);
        const bool cell_color=direct_assoc==GX3DE_SCI_ASSOC_CELL;
        if(cell_color&&object->opacity_array>=0)return GX3DE_UNSUPPORTED;
        vtkFieldData* fields=cell_color?static_cast<vtkFieldData*>(data->GetCellData()):static_cast<vtkFieldData*>(data->GetPointData());
        auto display_array=[&](int64_t index)->vtkDataArray*{
            if(index<0)return nullptr;
            auto* source=scientific_array_by_index(*object->scientific,
                static_cast<uint64_t>(index),nullptr);
            if(!source)return nullptr;
            for(int j=0;j<fields->GetNumberOfArrays();++j)
                if(fields->GetArray(j)==source)return cell_color?poly->GetCellData()->GetArray(j):poly->GetPointData()->GetArray(j);
            return nullptr;};
        const auto tuples=cell_color?poly->GetNumberOfCells():poly->GetNumberOfPoints();
        vtkDataArray* direct=display_array(object->color_array);
        vtkDataArray* opacity=display_array(object->opacity_array);
        if((object->color_array>=0&&!direct)||(object->opacity_array>=0&&!opacity)||
           (direct&&direct->GetNumberOfTuples()!=tuples)||
           (opacity&&opacity->GetNumberOfTuples()!=poly->GetNumberOfPoints()))
            return GX3DE_DEGENERATE;
        vtkDataArray* scalar_values=nullptr;
        if(!direct&&scalar&&scalar_assoc==GX3DE_SCI_ASSOC_POINT&&object->style.scalar_coloring){
            if(scalar->GetName())scalar_values=poly->GetPointData()->GetArray(scalar->GetName());
            else if(array_id>=0)scalar_values=poly->GetPointData()->GetArray(array_id);}
        auto lut=renderer_lut(object->presentation);
        if(scalar_values){double range[2];scalar->GetRange(range);
            if(object->presentation.use_scalar_range){range[0]=object->presentation.scalar_min;
                range[1]=object->presentation.scalar_max;}
            if(range[0]==range[1])range[1]=range[0]+1;
            lut->SetTableRange(range);lut->Build();}
        vtkNew<vtkUnsignedCharArray> colors;colors->SetName("__gx3de_display_rgba");
        colors->SetNumberOfComponents(4);colors->SetNumberOfTuples(tuples);
        for(vtkIdType i=0;i<tuples;++i){
            double rgb[3]={object->style.color.r,object->style.color.g,object->style.color.b};
            if(direct)for(int j=0;j<3;++j)rgb[j]=direct->GetComponent(i,j);
            else if(scalar_values&&i<scalar_values->GetNumberOfTuples())
                lut->GetColor(scalar_values->GetComponent(i,0),rgb);
            double alpha=object->opacity;
            if(opacity)alpha*=opacity->GetComponent(i,0);
            if(direct&&direct->GetNumberOfComponents()==4)alpha*=direct->GetComponent(i,3);
            alpha=std::clamp(alpha,0.0,1.0);
            if(alpha<1.0-1.0/255.0)translucent_rgba=true;
            colors->SetTuple4(i,std::lround(std::clamp(rgb[0],0.0,1.0)*255),
                std::lround(std::clamp(rgb[1],0.0,1.0)*255),
                std::lround(std::clamp(rgb[2],0.0,1.0)*255),std::lround(alpha*255));}
        auto display=vtkSmartPointer<vtkPolyData>::New();display->ShallowCopy(poly);
        if(cell_color)display->GetCellData()->AddArray(colors);else display->GetPointData()->AddArray(colors);poly=display;direct_rgba=true;
    }
    if((object->presentation.sphere_glyphs||roles.radius_array>=0)&&poly->GetNumberOfPoints()>0){
        const auto glyph_count=static_cast<uint64_t>(poly->GetNumberOfPoints());
        vtkNew<vtkSphereSource> sphere;
        sphere->SetThetaResolution(glyph_count>20000?8:12);
        sphere->SetPhiResolution(glyph_count>20000?6:8);
        sphere->SetRadius(1.0);
        sphere->Update();
        const auto faces=static_cast<uint64_t>(sphere->GetOutput()->GetNumberOfPolys());
        if(glyph_count>100000||faces==0||displayed_triangles>display_budget||
           glyph_count>(display_budget-displayed_triangles)/faces)return GX3DE_RANGE;
        displayed_triangles+=glyph_count*faces;
        vtkNew<vtkGlyph3DMapper> mapper;mapper->SetInputData(poly);
        mapper->SetSourceConnection(sphere->GetOutputPort());
        if(roles.radius_array>=0){auto* radius=scientific_array_by_index(*object->scientific,
            static_cast<uint64_t>(roles.radius_array),nullptr);
            if(radius&&radius->GetName()){mapper->SetScaleArray(radius->GetName());
                mapper->SetScaleModeToScaleByMagnitude();mapper->SetScaleFactor(1.0);}}
        else {double b[6];poly->GetBounds(b);const double span=std::max({b[1]-b[0],b[3]-b[2],b[5]-b[4],1.0});
            mapper->SetScaleModeToNoDataScaling();mapper->SetScaleFactor(span*0.012);}
        if(direct_rgba){mapper->SetScalarModeToUsePointFieldData();
            mapper->SelectColorArray("__gx3de_display_rgba");
            mapper->SetColorModeToDirectScalars();mapper->ScalarVisibilityOn();}
        else if(scalar&&scalar_assoc==GX3DE_SCI_ASSOC_POINT&&object->style.scalar_coloring){mapper->SetScalarModeToUsePointFieldData();
            if(scalar->GetName())mapper->SelectColorArray(scalar->GetName());
            mapper->SetLookupTable(renderer_lut(object->presentation));
            double r[2];scalar->GetRange(r);if(object->presentation.use_scalar_range){r[0]=object->presentation.scalar_min;r[1]=object->presentation.scalar_max;}
            mapper->SetScalarRange(r);mapper->ScalarVisibilityOn();}
        else mapper->ScalarVisibilityOff();
        renderer_apply_clips(mapper,rv.viewport->view);
        vtkNew<vtkActor> actor;actor->SetMapper(mapper);actor->SetUserMatrix(renderer_matrix(world(object)));
        renderer_apply_style(actor,object,rv.viewport->view);
        if(direct_rgba){actor->GetProperty()->SetOpacity(1.0);
            if(translucent_rgba)actor->ForceTranslucentOn();}
        rv.renderer->AddActor(actor);rv.props.push_back({actor,object,GX3DE_PICK_SCIENTIFIC,world(object)});
    }else renderer_add_prop(rv,object,GX3DE_PICK_SCIENTIFIC,poly,world(object),rv.viewport->view,
                           scalar!=nullptr,scalar_assoc,array_id,scalar,direct_rgba,translucent_rgba);
    if(object->presentation.show_vectors&&roles.vector_array>=0){
        const auto max_samples=object->presentation.max_vector_glyphs?
            object->presentation.max_vector_glyphs:2000;
        uint64_t count=0;auto rc=gx3de_scientific_vector_samples(object,
            static_cast<uint64_t>(roles.vector_array),max_samples,1,nullptr,0,&count);
        if(rc!=GX3DE_RANGE&&rc!=GX3DE_OK)return rc;
        std::vector<gx3de_scientific_vector_sample> samples(count);
        for(auto& s:samples)s.struct_size=sizeof(s);
        rc=gx3de_scientific_vector_samples(object,static_cast<uint64_t>(roles.vector_array),
            max_samples,1,samples.data(),count,&count);if(rc!=GX3DE_OK)return rc;
        vtkNew<vtkPoints> points;vtkNew<vtkDoubleArray> vectors;vectors->SetName("gx3de_display_vectors");
        vectors->SetNumberOfComponents(3);double largest=0;
        for(const auto& s:samples){points->InsertNextPoint(s.position.x,s.position.y,s.position.z);
            vectors->InsertNextTuple3(s.vector.x,s.vector.y,s.vector.z);
            largest=std::max(largest,length(s.vector));}
        if(points->GetNumberOfPoints()>0&&largest>0){vtkNew<vtkPolyData> vector_poly;
            vector_poly->SetPoints(points);vector_poly->GetPointData()->AddArray(vectors);
            vtkNew<vtkArrowSource> arrow;vtkNew<vtkGlyph3DMapper> glyph;
            glyph->SetInputData(vector_poly);glyph->SetSourceConnection(arrow->GetOutputPort());
            glyph->SetOrientationArray("gx3de_display_vectors");glyph->SetOrientationModeToDirection();
            glyph->SetScaleArray("gx3de_display_vectors");glyph->SetScaleModeToScaleByMagnitude();
            double b[6];data->GetBounds(b);double span=std::max({b[1]-b[0],b[3]-b[2],b[5]-b[4],1.0});
            glyph->SetScaleFactor(span/(50*largest));glyph->ScalarVisibilityOff();
            renderer_apply_clips(glyph,rv.viewport->view);
            vtkNew<vtkActor> actor;actor->SetMapper(glyph);actor->GetProperty()->SetColor(1.0,0.45,0.15);
            actor->GetProperty()->SetOpacity(object->opacity);rv.renderer->AddActor(actor);
            rv.props.push_back({actor,object,GX3DE_PICK_SCIENTIFIC,identity()});}}
    return GX3DE_OK;
}

static gx3de_result renderer_add_repeats(gx3de_render_viewport& rv,
                                         uint64_t& displayed_triangles,uint64_t budget) {
    auto* scene=rv.viewport->view->scene;
    for(auto* result:scene->repeats){if(!result->presentation_enabled||!result->source||
            !result->source->visible||result->source->opacity<=0)continue;
        const auto count=result->data.matches.size();
        const auto triangles=result->data.prototype.triangles.size()/3;
        if(count>100000||triangles>budget||displayed_triangles>budget||
           count*triangles+result->data.remainder.triangles.size()/3>
           budget-displayed_triangles)return GX3DE_RANGE;
        displayed_triangles+=count*triangles+result->data.remainder.triangles.size()/3;
        auto poly=renderer_mesh_poly(result->data.prototype);
        vtkNew<vtkPolyDataMapper> shared;shared->SetInputData(poly);shared->ScalarVisibilityOff();
        renderer_apply_clips(shared,rv.viewport->view);
        for(size_t i=0;i<count;++i){const auto& m=result->data.matches[i];
            auto placement=identity();
            for(int row=0;row<3;++row)for(int col=0;col<3;++col)
                placement.m[col*4+row]=m.rotation[row][col];
            for(int axis=0;axis<3;++axis)placement.m[12+axis]=m.center[axis];
            const auto pose=product(result->source_world,placement);
            vtkNew<vtkActor> actor;actor->SetMapper(shared);actor->SetUserMatrix(renderer_matrix(pose));
            renderer_apply_style(actor,result->source,rv.viewport->view);
            rv.renderer->AddActor(actor);
            rv.props.push_back({actor,result->source,GX3DE_PICK_REPEAT,pose});}
        if(!result->data.remainder.triangles.empty()){
            auto rest=renderer_mesh_poly(result->data.remainder);
            renderer_add_prop(rv,result->source,GX3DE_PICK_REPEAT,rest,
                              result->source_world,rv.viewport->view);}}
    return GX3DE_OK;
}

static double renderer_pixel_world(const gx3de_viewport* vp,gx3de_vec3 center,double px) {
    const auto& c=vp->view->camera;
    const double distance=c.orthographic?length(sub(c.position,c.target)):
        std::max(1e-6,length(sub(c.position,center)));
    return std::max(1e-9,2*distance*std::tan(c.vertical_fov_degrees*
        3.141592653589793/360.0)*px/std::max<uint32_t>(1,vp->height));
}
static bool renderer_clip_world_segment(const gx3de_view* view,gx3de_segment3& segment) {
    double t0=0,t1=1;const auto start=segment.a,delta=sub(segment.b,segment.a);
    auto halfspace=[&](gx3de_vec3 origin,gx3de_vec3 normal)->bool {
        const double a=dot(sub(start,origin),normal),b=dot(delta,normal);
        if(std::abs(b)<1e-15)return a>=-1e-10;
        const double t=-a/b;
        if(b>0)t0=std::max(t0,t);else t1=std::min(t1,t);
        return t0<=t1+1e-12;
    };
    for(const auto& clip:view->clips)if(clip.enabled){const double sign=clip.keep_positive?1.0:-1.0;
        if(!halfspace(clip.origin,mul(clip.normal,sign)))return false;}
    if(view->clip_box.enabled){const auto& b=view->clip_box.world_bounds;
        const gx3de_vec3 origins[6]={{b.min.x,0,0},{b.max.x,0,0},
            {0,b.min.y,0},{0,b.max.y,0},{0,0,b.min.z},{0,0,b.max.z}};
        const gx3de_vec3 normals[6]={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
        for(int i=0;i<6;++i)if(!halfspace(origins[i],normals[i]))return false;}
    if(t1<0||t0>1)return false;
    t0=std::clamp(t0,0.0,1.0);t1=std::clamp(t1,0.0,1.0);
    if(t1<t0)return false;
    segment.a=add(start,mul(delta,t0));segment.b=add(start,mul(delta,t1));return true;
}
static bool renderer_point_inside(const gx3de_view* view,gx3de_vec3 point) {
    gx3de_segment3 tiny{point,point};return renderer_clip_world_segment(view,tiny);
}
static void renderer_add_world_lines(gx3de_render_viewport& rv,
    const std::vector<gx3de_segment3>& segments,const gx3de_curve_style& style,
    gx3de_gizmo* gizmo=nullptr,uint32_t handle=0) {
    if(!style.visible||style.opacity<=0||segments.empty())return;
    vtkNew<vtkPoints> points;points->SetDataTypeToDouble();vtkNew<vtkCellArray> lines;
    for(auto seg:segments){if(!renderer_clip_world_segment(rv.viewport->view,seg))continue;
        const vtkIdType a=points->InsertNextPoint(seg.a.x,seg.a.y,seg.a.z);
        const vtkIdType b=points->InsertNextPoint(seg.b.x,seg.b.y,seg.b.z);
        vtkIdType ids[2]={a,b};lines->InsertNextCell(2,ids);}
    if(points->GetNumberOfPoints()==0)return;
    vtkNew<vtkPolyData> poly;poly->SetPoints(points);poly->SetLines(lines);
    vtkNew<vtkPolyDataMapper> mapper;mapper->SetInputData(poly);mapper->ScalarVisibilityOff();
    renderer_apply_clips(mapper,rv.viewport->view);
    vtkNew<vtkActor> actor;actor->SetMapper(mapper);actor->GetProperty()->LightingOff();
    actor->GetProperty()->SetColor(style.color.r,style.color.g,style.color.b);
    actor->GetProperty()->SetLineWidth(style.line_width);
    actor->GetProperty()->SetOpacity(style.opacity);rv.renderer->AddActor(actor);
    rv.overlay_actors.push_back(actor);
    if(gizmo)rv.props.push_back({actor,gizmo->spec.object,0,identity(),gizmo,handle});
}
static void renderer_add_gizmos(gx3de_render_viewport& rv) {
    auto* view=rv.viewport->view;
    auto axis=[&](const gx3de_mat4& pose,int i){return gx3de_vec3{
        pose.m[4*i],pose.m[4*i+1],pose.m[4*i+2]};};
    const gx3de_rgb colors[3]={{1.0,0.25,0.23},{0.25,0.94,0.31},{0.27,0.53,1.0}};
    auto line=[&](std::vector<gx3de_segment3> parts,gx3de_rgb color,double width,
                  gx3de_gizmo* gizmo,uint32_t handle){gx3de_curve_style s{
        sizeof(s),1,color,width,1.0,{}};renderer_add_world_lines(rv,parts,s,gizmo,handle);};
    if(view->axes.show_world||view->axes.show_local||view->axes.show_reference){
        auto draw=[&](gx3de_vec3 pivot,const gx3de_mat4& pose){
            const double span=renderer_pixel_world(rv.viewport,pivot,view->axes.size_pixels);
            for(int i=0;i<3;++i){auto direction=axis(pose,i);
                const double length_axis=length(direction);if(length_axis<1e-12)continue;
                line({{pivot,add(pivot,mul(direction,span/length_axis))}},colors[i],2,nullptr,0);}};
        if(view->axes.show_world)draw({0,0,0},identity());
        if(view->axes.show_local&&view->axes.local_object)
            draw(apply(world(view->axes.local_object),{0,0,0}),world(view->axes.local_object));
        if(view->axes.show_reference&&view->axes.reference_axis){gx3de_vec3 at{},direction{};
            if(gx3de_anchor_position(view->axes.reference_axis,&at)==GX3DE_OK&&
               (gx3de_anchor_tangent(view->axes.reference_axis,&direction)==GX3DE_OK||
                gx3de_anchor_normal(view->axes.reference_axis,&direction)==GX3DE_OK)){
                const double magnitude=length(direction);
                if(magnitude>1e-12){const double span=renderer_pixel_world(rv.viewport,at,
                    view->axes.size_pixels);
                    direction=mul(direction,span/magnitude);
                    line({{sub(at,direction),add(at,direction)}},
                        {1.0,0.78,0.19},2.0,nullptr,0);}}}}
    for(auto* gizmo:view->gizmos){const auto& s=gizmo->spec;
        if(!s.visible||!s.object||!s.object->visible)continue;
        gx3de_vec3 pivot{};
        if(s.pivot_mode==GX3DE_GIZMO_PIVOT_EXPLICIT)pivot=s.world_pivot;
        else if(s.pivot_mode==GX3DE_GIZMO_PIVOT_ANCHOR){
            if(!s.anchor||gx3de_anchor_position(s.anchor,&pivot)!=GX3DE_OK)continue;}
        else pivot=apply(world(s.object),{0,0,0});
        const auto pose=world(s.object);
        gx3de_vec3 basis[3]{};for(int i=0;i<3;++i){basis[i]=s.space==GX3DE_GIZMO_SPACE_WORLD?
            gx3de_vec3{i==0?1.0:0.0,i==1?1.0:0.0,i==2?1.0:0.0}:axis(pose,i);
            const double n=length(basis[i]);if(n>1e-12)basis[i]=mul(basis[i],1.0/n);}
        const double span=renderer_pixel_world(rv.viewport,pivot,s.size_pixels);
        if(!(span>0)||!std::isfinite(span))continue;
        for(uint32_t handle=1;handle<=10;++handle){
            const uint32_t family=handle<=3?1u:handle<=6?2u:handle==7?4u:8u;
            if(!(s.families&family))continue;
            std::vector<gx3de_segment3> parts;gx3de_rgb color=colors[(handle-1)%3];
            if(handle<=3){const auto end=add(pivot,mul(basis[handle-1],span));
                parts.push_back({pivot,end});
                auto flank=basis[handle%3];
                parts.push_back({end,add(add(pivot,mul(basis[handle-1],span*.83)),mul(flank,span*.07))});
                parts.push_back({end,sub(add(pivot,mul(basis[handle-1],span*.83)),mul(flank,span*.07))});}
            else if(handle<=6){const int first=handle==4?0:handle==5?1:2;
                const int second=(first+1)%3;
                const auto a=add(pivot,mul(basis[first],span*.32));
                const auto b=add(pivot,mul(basis[second],span*.32));
                const auto corner=add(a,mul(basis[second],span*.32));
                parts={{a,corner},{corner,b},{b,a}};color={0.95,0.76,0.2};}
            else if(handle==7){const auto a=mul(basis[0],span*.09),b=mul(basis[1],span*.09);
                parts={{sub(pivot,a),add(pivot,a)},{sub(pivot,b),add(pivot,b)}};
                color={0.95,0.95,0.95};}
            else {const int normal_axis=int(handle)-8,first=(normal_axis+1)%3,
                           second=(normal_axis+2)%3;
                constexpr int steps=48;const double radius=span*.79;
                for(int j=0;j<steps;++j){const double a=2*3.141592653589793*j/steps,
                    b=2*3.141592653589793*(j+1)/steps;
                    const auto p=add(pivot,add(mul(basis[first],radius*std::cos(a)),
                        mul(basis[second],radius*std::sin(a))));
                    const auto q=add(pivot,add(mul(basis[first],radius*std::cos(b)),
                        mul(basis[second],radius*std::sin(b))));parts.push_back({p,q});}
                color=colors[normal_axis];}
            if(gizmo->active==handle||gizmo->hover==handle)color={1.0,0.91,0.28};
            line(std::move(parts),color,gizmo->active==handle?5.0:3.0,gizmo,handle);
        }
    }
}
static void renderer_add_planar_gizmos(gx3de_render_viewport& rv) {
    const auto* view=rv.viewport->view;
    const auto forward=sub(view->camera.target,view->camera.position);
    if(length(forward)<1e-12)return;
    auto right=cross(forward,view->camera.up);
    if(length(right)<1e-12)return;
    right=mul(right,1.0/length(right));
    auto up=cross(right,forward);up=mul(up,1.0/length(up));
    auto draw=[&](const std::vector<gx3de_segment3>& parts,gx3de_rgb color,double width){
        gx3de_curve_style style{sizeof(style),1,color,width,1.0,{}};
        renderer_add_world_lines(rv,parts,style);
    };
    for(auto* object:view->scene->objects)if(object->visible&&object->opacity>0)
    for(auto* assignment:object->planar_textures)if(assignment->gizmo_visible){
        gx3de_vec3 points[9]{};bool okay=true;
        for(uint32_t h=1;h<=8;++h)
            if(gx3de_planar_texture_gizmo_handle_world(assignment,h,&points[h])!=GX3DE_OK)
                okay=false;
        if(!okay)continue;
        draw({{points[2],points[3]},{points[3],points[4]},
              {points[4],points[5]},{points[5],points[2]}},{0.08,0.95,0.98},3);
        const auto top=mul(add(points[4],points[5]),.5);
        draw({{top,points[8]}},{.91,.44,1.0},2);
        for(uint32_t h=1;h<=8;++h){
            const double span=renderer_pixel_world(rv.viewport,points[h],h==1?9.0:7.0);
            if(!(span>0))continue;
            const auto r=mul(right,span*.5),u=mul(up,span*.5);
            if(h==1)draw({{sub(points[h],r),add(points[h],r)},
                          {sub(points[h],u),add(points[h],u)}},{1.0,.90,.12},3);
            else if(h==8)draw({{add(points[h],r),add(points[h],u)},
                               {add(points[h],u),sub(points[h],r)},
                               {sub(points[h],r),sub(points[h],u)},
                               {sub(points[h],u),add(points[h],r)}},{.91,.44,1.0},3);
            else {const auto a=add(add(points[h],r),u),b=add(sub(points[h],r),u),
                            c=sub(sub(points[h],r),u),d=sub(add(points[h],r),u);
                draw({{a,b},{b,c},{c,d},{d,a}},h<=5?gx3de_rgb{1,1,1}:
                    gx3de_rgb{1.0,.52,.08},2.5);}
        }
    }
    for(auto* object:view->scene->objects)if(object->visible&&object->opacity>0)
    for(auto* assignment:object->curved_textures)if(assignment->gizmo_visible){
        std::vector<gx3de_segment3> footprint;
        footprint.reserve(assignment->boundary.size());
        const auto pose=world(object);
        for(const auto& segment:assignment->boundary)
            footprint.push_back({apply(pose,segment.a),apply(pose,segment.b)});
        if(!footprint.empty())draw(footprint,{0.08,0.95,0.98},2.0);
        for(uint32_t h=1;h<=8;++h){
            gx3de_vec3 p{};
            if(gx3de_curved_texture_gizmo_handle_world(assignment,h,&p)!=GX3DE_OK)continue;
            const double span=renderer_pixel_world(rv.viewport,p,h==1?9.0:7.0);
            if(!(span>0))continue;
            const auto r=mul(right,span*.5),u=mul(up,span*.5);
            draw({{sub(p,r),add(p,r)},{sub(p,u),add(p,u)}},
                 h==1?gx3de_rgb{1.0,.90,.12}:gx3de_rgb{1,1,1},2.5);
        }
    }
}
static void renderer_add_marker_geometry(gx3de_render_viewport& rv,
    gx3de_anchor* anchor,const gx3de_marker_style& style) {
    if(!anchor||!style.visible)return;
    if(anchor->object&&(!anchor->object->visible||anchor->object->opacity<=0))return;
    gx3de_vec3 at{};if(gx3de_anchor_position(anchor,&at)!=GX3DE_OK||
        !renderer_point_inside(rv.viewport->view,at))return;
    const double span=renderer_pixel_world(rv.viewport,at,style.size_pixels);
    if(style.kind==GX3DE_MARKER_CROSS){gx3de_curve_style line{
        sizeof(gx3de_curve_style),1,style.color,style.line_width,1.0,{}};
        std::vector<gx3de_segment3> segments{{{at.x-span/2,at.y,at.z},{at.x+span/2,at.y,at.z}},
            {{at.x,at.y-span/2,at.z},{at.x,at.y+span/2,at.z}},
            {{at.x,at.y,at.z-span/2},{at.x,at.y,at.z+span/2}}};
        renderer_add_world_lines(rv,segments,line);
    }else {vtkNew<vtkSphereSource> sphere;sphere->SetCenter(at.x,at.y,at.z);
        sphere->SetRadius(span*(style.highlighted?0.65:0.5));
        sphere->SetThetaResolution(12);sphere->SetPhiResolution(8);
        vtkNew<vtkPolyDataMapper> mapper;mapper->SetInputConnection(sphere->GetOutputPort());
        renderer_apply_clips(mapper,rv.viewport->view);
        vtkNew<vtkActor> actor;actor->SetMapper(mapper);actor->GetProperty()->LightingOff();
        actor->GetProperty()->SetColor(style.color.r,style.color.g,style.color.b);
        rv.renderer->AddActor(actor);rv.overlay_actors.push_back(actor);}
    gx3de_vec3 tangent{};bool indicator=false;
    if(style.kind==GX3DE_MARKER_NORMAL)
        indicator=gx3de_anchor_normal(anchor,&tangent)==GX3DE_OK;
    else if(style.kind==GX3DE_MARKER_TANGENT)
        indicator=gx3de_anchor_tangent(anchor,&tangent)==GX3DE_OK;
    if(indicator){const double n=length(tangent);
        if(std::isfinite(n)&&n>1e-12){gx3de_curve_style line{
            sizeof(gx3de_curve_style),1,style.color,style.line_width,1.0,{}};
            renderer_add_world_lines(rv,{{at,add(at,mul(tangent,span*3.0/n))}},line);}}
    if(style.highlighted&&anchor->object&&anchor->object->mesh){
        const auto& m=*anchor->object->mesh;std::vector<gx3de_segment3> edges;
        const auto pose=world(anchor->object);
        if(anchor->kind==GX3DE_ANCHOR_EDGE&&anchor->vertex<m.vertices.size()&&
           anchor->vertex_b<m.vertices.size())edges.push_back({
            apply(pose,m.vertices[anchor->vertex]),apply(pose,m.vertices[anchor->vertex_b])});
        else if(anchor->kind==GX3DE_ANCHOR_FACE&&anchor->triangle<m.triangles.size()/3){
            const size_t base=size_t(anchor->triangle)*3;
            for(size_t i=0;i<3;++i)edges.push_back({
                apply(pose,m.vertices[m.triangles[base+i]]),
                apply(pose,m.vertices[m.triangles[base+(i+1)%3]])});}
        if(!edges.empty()){gx3de_curve_style line{sizeof(gx3de_curve_style),1,
            style.color,std::max(style.line_width,3.0),1.0,{}};
            renderer_add_world_lines(rv,edges,line);}}
}

static gx3de_result renderer_add_overlays(gx3de_render_viewport& rv) {
    auto* scene=rv.viewport->view->scene;
    if(scene->markers.size()>10000||scene->measurements.size()>10000||
       rv.viewport->view->gizmos.size()>64)return GX3DE_RANGE;
    if(auto* plane=rv.viewport->view->working_plane){
        if(scene->objects.size()>10000)return GX3DE_RANGE;
        double extent=renderer_pixel_world(rv.viewport,plane->origin,110.0);
        gx3de_bounds bounds{};bool have_bounds=false;
        for(auto* object:scene->objects)if(object->visible){gx3de_bounds b{};
            if(gx3de_object_bounds(object,1,&b)!=GX3DE_OK)continue;
            if(!have_bounds){bounds=b;have_bounds=true;}
            else {bounds.min={std::min(bounds.min.x,b.min.x),std::min(bounds.min.y,b.min.y),
                std::min(bounds.min.z,b.min.z)};
                bounds.max={std::max(bounds.max.x,b.max.x),std::max(bounds.max.y,b.max.y),
                std::max(bounds.max.z,b.max.z)};}}
        if(have_bounds)extent=std::max(extent,0.6*length(sub(bounds.max,bounds.min)));
        if(!std::isfinite(extent)||extent<=0)return GX3DE_RANGE;
        extent=std::min(extent,1000000.0);
        std::vector<gx3de_segment3> grid,outline;
        auto position=[&](double u,double v){return add(plane->origin,
            add(mul(plane->u,u*extent),mul(plane->v,v*extent)));};
        for(int i=-5;i<=5;++i){const double t=i/5.0;
            grid.push_back({position(t,-1),position(t,1)});
            grid.push_back({position(-1,t),position(1,t)});}
        outline={{position(-1,-1),position(1,-1)},
                 {position(1,-1),position(1,1)},
                 {position(1,1),position(-1,1)},
                 {position(-1,1),position(-1,-1)}};
        gx3de_curve_style grid_style{sizeof(grid_style),1,{0.34,0.45,0.53},1.0,0.56,{}};
        gx3de_curve_style outline_style{sizeof(outline_style),1,{0.53,0.68,0.75},2.0,0.85,{}};
        renderer_add_world_lines(rv,grid,grid_style);
        renderer_add_world_lines(rv,outline,outline_style);
    }
    for(auto* section:scene->sections)if(section->style.visible){
        if(section->segments.size()>1000000)return GX3DE_RANGE;
        renderer_add_world_lines(rv,section->segments,section->style);}
    for(auto* profile:scene->profiles)if(profile->style.visible){
        size_t points=0;std::vector<gx3de_segment3> lines;
        for(const auto& contour:profile->contours){points+=contour.points.size();
            if(points>1000000)return GX3DE_RANGE;
            for(size_t i=1;i<contour.points.size();++i)
                lines.push_back({contour.points[i-1],contour.points[i]});
            if(contour.closed&&contour.points.size()>2)
                lines.push_back({contour.points.back(),contour.points.front()});}
        renderer_add_world_lines(rv,lines,profile->style);}
    for(auto* marker:scene->markers)if(!marker->view||marker->view==rv.viewport->view)
        renderer_add_marker_geometry(rv,marker->anchor,marker->style);
    if(rv.viewport->view->selection){gx3de_marker_style selected{
        sizeof(gx3de_marker_style),1,GX3DE_MARKER_POINT,1,{1.0,0.92,0.12},12.0,3.0,{}};
        renderer_add_marker_geometry(rv,rv.viewport->view->selection,selected);}
    for(auto* measurement:scene->measurements)if(measurement->style.visible){
        gx3de_anchor* anchors[]={measurement->a,measurement->b,measurement->c,measurement->d};
        std::vector<gx3de_vec3> points;
        gx3de_marker_style marker{sizeof(gx3de_marker_style),1,GX3DE_MARKER_POINT,0,
            measurement->style.color,measurement->style.marker_size_pixels,
            measurement->style.line_width,{}};
        for(auto* anchor:anchors)if(anchor){gx3de_vec3 point{};
            if(gx3de_anchor_position(anchor,&point)==GX3DE_OK){points.push_back(point);
                renderer_add_marker_geometry(rv,anchor,marker);}}
        if(points.size()>1){std::vector<gx3de_segment3> lines;
            if(measurement->kind==GX3DE_ANGLE_THREE_POINTS&&points.size()>=3){
                lines.push_back({points[0],points[1]});lines.push_back({points[1],points[2]});}
            else lines.push_back({points[0],points[1]});
            gx3de_curve_style line{sizeof(gx3de_curve_style),1,measurement->style.color,
                measurement->style.line_width,1.0,{}};
            renderer_add_world_lines(rv,lines,line);}
        if(measurement->style.show_value&&!points.empty()){
            gx3de_measure_value value{};value.struct_size=sizeof(value);
            if(gx3de_measure_evaluate(measurement,&value)==GX3DE_OK){
                char label[48];std::snprintf(label,sizeof(label),"%.5g",value.value);
                vtkNew<vtkVectorText> text;text->SetText(label);
                vtkNew<vtkPolyDataMapper> mapper;mapper->SetInputConnection(text->GetOutputPort());
                const auto at=points.size()>1?mul(add(points[0],points[1]),0.5):points[0];
                vtkNew<vtkFollower> actor;actor->SetMapper(mapper);actor->SetCamera(rv.renderer->GetActiveCamera());
                actor->SetPosition(at.x,at.y,at.z);
                const double scale=renderer_pixel_world(rv.viewport,at,14.0);
                actor->SetScale(scale,scale,scale);actor->GetProperty()->LightingOff();
                actor->GetProperty()->SetColor(measurement->style.color.r,
                    measurement->style.color.g,measurement->style.color.b);
                rv.renderer->AddActor(actor);rv.overlay_actors.push_back(actor);}}
    }
    renderer_add_gizmos(rv);
    renderer_add_planar_gizmos(rv);
    return GX3DE_OK;
}

static void renderer_key_add(std::string& key,const void* bytes,size_t count) {
    key.append(static_cast<const char*>(bytes),count);
}
static void renderer_checkerboard(gx3de_render_viewport& rv) {
    const auto& b=rv.viewport->view->checkerboard;
    if(!b.enabled){rv.renderer->TexturedBackgroundOff();return;}
    const int width=int(rv.viewport->width),height=int(rv.viewport->height);
    vtkNew<vtkImageData> image;image->SetDimensions(width,height,1);
    image->AllocateScalars(VTK_UNSIGNED_CHAR,3);
    for(int y=0;y<height;++y)for(int x=0;x<width;++x){
        auto* pixel=static_cast<unsigned char*>(image->GetScalarPointer(x,y,0));
        const auto& color=((x/b.checker_pixels+y/b.checker_pixels)&1)?b.first:b.second;
        pixel[0]=static_cast<unsigned char>(std::lround(255*color.r));
        pixel[1]=static_cast<unsigned char>(std::lround(255*color.g));
        pixel[2]=static_cast<unsigned char>(std::lround(255*color.b));
    }
    vtkNew<vtkTexture> texture;texture->SetInputData(image);texture->InterpolateOff();
    texture->RepeatOff();rv.renderer->SetBackgroundTexture(texture);
    rv.renderer->TexturedBackgroundOn();rv.renderer->GradientBackgroundOff();
}
static void renderer_navcube(gx3de_target* target,gx3de_render_viewport& rv) {
    const auto& s=rv.viewport->view->navcube;
    const double size=std::min({double(s.size_pixels),
        double(rv.viewport->width)-2*s.margin_pixels,
        double(rv.viewport->height)-2*s.margin_pixels});
    if(!s.visible||size<=0){if(rv.navcube_renderer)target->window->RemoveRenderer(rv.navcube_renderer);
        rv.navcube_renderer=nullptr;rv.navcube_actors.clear();return;}
    if(!rv.navcube_renderer){
        rv.navcube_renderer=vtkSmartPointer<vtkRenderer>::New();
        rv.navcube_renderer->SetLayer(1);
        rv.navcube_renderer->SetPreserveColorBuffer(true);
        rv.navcube_renderer->SetInteractive(false);
        rv.navcube_renderer->AutomaticLightCreationOff();
        for(int sx=-1;sx<=1;++sx)for(int sy=-1;sy<=1;++sy)
            for(int sz=-1;sz<=1;++sz){
                if(!sx&&!sy&&!sz)continue;
                vtkNew<vtkCubeSource> box;
                box->SetCenter(sx*.79,sy*.79,sz*.79);
                box->SetXLength(sx?.40:1.16);
                box->SetYLength(sy?.40:1.16);
                box->SetZLength(sz?.40:1.16);
                vtkNew<vtkPolyDataMapper> mapper;mapper->SetInputConnection(box->GetOutputPort());
                vtkNew<vtkActor> actor;actor->SetMapper(mapper);
                actor->GetProperty()->SetAmbient(1);actor->GetProperty()->SetDiffuse(0);
                actor->GetProperty()->EdgeVisibilityOn();
                actor->GetProperty()->SetEdgeColor(.10,.12,.16);
                actor->GetProperty()->SetLineWidth(1.0);
                rv.navcube_renderer->AddActor(actor);rv.navcube_actors.push_back(actor);
            }
        target->window->AddRenderer(rv.navcube_renderer);
    }
    const double left=(s.corner&1u)?rv.viewport->width-s.margin_pixels-size:s.margin_pixels;
    const double top=(s.corner&2u)?rv.viewport->height-s.margin_pixels-size:s.margin_pixels;
    const double W=target->width,H=target->height;
    rv.navcube_renderer->SetViewport((rv.viewport->x+left)/W,
        1.0-(rv.viewport->y+top+size)/H,(rv.viewport->x+left+size)/W,
        1.0-(rv.viewport->y+top)/H);
    auto* camera=rv.navcube_renderer->GetActiveCamera();
    const auto& c=rv.viewport->view->camera;
    auto direction=sub(c.position,c.target);direction=mul(direction,1.0/length(direction));
    camera->SetPosition(direction.x*5,direction.y*5,direction.z*5);
    camera->SetFocalPoint(0,0,0);camera->SetViewUp(c.up.x,c.up.y,c.up.z);
    camera->SetViewAngle(35);camera->SetClippingRange(.1,20);
    camera->SetParallelProjection(false);
    const uint32_t synced=navcube_synced(rv.viewport->view);
    size_t actor_index=0;
    for(int sx=-1;sx<=1;++sx)for(int sy=-1;sy<=1;++sy)
        for(int sz=-1;sz<=1;++sz){
            if(!sx&&!sy&&!sz)continue;
            const uint32_t region=uint32_t(1+9*(sx+1)+3*(sy+1)+(sz+1));
            auto* property=rv.navcube_actors[actor_index++]->GetProperty();
            if(region==s.hover_region)property->SetColor(1,.63,.20);
            else if(region==s.active_region||region==synced)
                property->SetColor(.98,.82,.38);
            else if(sz)property->SetColor(.42,.66,.92);
            else if(sx)property->SetColor(.89,.45,.46);
            else property->SetColor(.49,.79,.58);
        }
}
static void renderer_orientation_indicator(gx3de_target* target,gx3de_render_viewport& rv) {
    const auto& s=rv.viewport->view->orientation;
    const double size=std::min({double(s.size_pixels),double(rv.viewport->width)-2*s.margin_pixels,
        double(rv.viewport->height)-2*s.margin_pixels});
    if(!s.visible||size<=0){if(rv.orientation_renderer)target->window->RemoveRenderer(rv.orientation_renderer);
        rv.orientation_renderer=nullptr;return;}
    if(!rv.orientation_renderer){
        rv.orientation_renderer=vtkSmartPointer<vtkRenderer>::New();
        auto* renderer=rv.orientation_renderer.GetPointer();
        renderer->SetLayer(1);renderer->SetPreserveColorBuffer(true);renderer->InteractiveOff();
        vtkNew<vtkAxesActor> axes;axes->SetTotalLength(1,1,1);
        axes->SetShaftTypeToCylinder();axes->SetCylinderRadius(.025);
        for(auto* label:{axes->GetXAxisCaptionActor2D(),axes->GetYAxisCaptionActor2D(),axes->GetZAxisCaptionActor2D()}) {
            label->GetCaptionTextProperty()->SetColor(.12,.15,.2);
            label->GetCaptionTextProperty()->ShadowOff();
        }
        renderer->AddActor(axes);target->window->AddRenderer(renderer);
    }
    const double left=(s.corner&1u)?rv.viewport->width-s.margin_pixels-size:s.margin_pixels;
    const double top=(s.corner&2u)?rv.viewport->height-s.margin_pixels-size:s.margin_pixels;
    rv.orientation_renderer->SetViewport((rv.viewport->x+left)/target->width,
        1.-(rv.viewport->y+top+size)/target->height,(rv.viewport->x+left+size)/target->width,
        1.-(rv.viewport->y+top)/target->height);
    // Center the presentation axes in their own viewport, independent of the
    // scientific origin, pan, zoom, units and model bounds. Follow camera roll.
    const auto& c=rv.viewport->view->camera;
    auto direction=sub(c.position,c.target);direction=mul(direction,1./length(direction));
    auto* camera=rv.orientation_renderer->GetActiveCamera();
    camera->SetFocalPoint(.5,.5,.5);
    camera->SetPosition(.5+5*direction.x,.5+5*direction.y,.5+5*direction.z);
    camera->SetViewUp(c.up.x,c.up.y,c.up.z);camera->ParallelProjectionOn();
    camera->SetParallelScale(1.15);camera->SetClippingRange(.1,20);
}
static std::string renderer_static_state_key(const gx3de_target* target) {
    std::string key;
#define GX3DE_RENDER_KEY(value) renderer_key_add(key,&(value),sizeof(value))
    GX3DE_RENDER_KEY(target->width);GX3DE_RENDER_KEY(target->height);
    GX3DE_RENDER_KEY(target->quality);GX3DE_RENDER_KEY(target->native_kind);
    const auto& graphics=target->engine->graphics;
    const uint32_t display_level=target->interaction_active&&graphics.interaction_lod_enabled?
        graphics.interaction_lod:graphics.normal_lod;
    GX3DE_RENDER_KEY(display_level);GX3DE_RENDER_KEY(graphics.shadow_policy);
    for(const auto* vp:target->viewports){
        GX3DE_RENDER_KEY(vp);GX3DE_RENDER_KEY(vp->x);GX3DE_RENDER_KEY(vp->y);
        GX3DE_RENDER_KEY(vp->width);GX3DE_RENDER_KEY(vp->height);
        const auto* v=vp->view;GX3DE_RENDER_KEY(v);
        GX3DE_RENDER_KEY(v->background);GX3DE_RENDER_KEY(v->checkerboard);
        GX3DE_RENDER_KEY(v->lighting);
        GX3DE_RENDER_KEY(v->positional_lights);
        GX3DE_RENDER_KEY(v->shadow_light_mask);
        GX3DE_RENDER_KEY(v->clip_box);GX3DE_RENDER_KEY(v->clips);
        GX3DE_RENDER_KEY(v->axes);GX3DE_RENDER_KEY(v->orientation);GX3DE_RENDER_KEY(v->selection);
        GX3DE_RENDER_KEY(v->working_plane);GX3DE_RENDER_KEY(v->interaction);
        const auto* s=v->scene;GX3DE_RENDER_KEY(s);GX3DE_RENDER_KEY(s->shadows_enabled);
        for(const auto* light:s->scientific_lights){GX3DE_RENDER_KEY(light);
            GX3DE_RENDER_KEY(light->spec);}
        for(const auto* cloud:s->particle_clouds){GX3DE_RENDER_KEY(cloud);
            GX3DE_RENDER_KEY(cloud->revision);GX3DE_RENDER_KEY(cloud->style);
            GX3DE_RENDER_KEY(cloud->transform);GX3DE_RENDER_KEY(cloud->visible);}
        for(const auto* o:s->objects){GX3DE_RENDER_KEY(o);
            GX3DE_RENDER_KEY(o->mesh);GX3DE_RENDER_KEY(o->scientific);
#ifdef GX3DE_WITH_OCCT
            GX3DE_RENDER_KEY(o->brep);
#endif
            GX3DE_RENDER_KEY(o->parent);GX3DE_RENDER_KEY(o->transform);
            GX3DE_RENDER_KEY(o->visible);GX3DE_RENDER_KEY(o->opacity);
            GX3DE_RENDER_KEY(o->scientific_transmittance);
            GX3DE_RENDER_KEY(o->casts_shadows);GX3DE_RENDER_KEY(o->receives_shadows);
            GX3DE_RENDER_KEY(o->style);GX3DE_RENDER_KEY(o->field_roles);
            GX3DE_RENDER_KEY(o->presentation);GX3DE_RENDER_KEY(o->opacity_array);
            GX3DE_RENDER_KEY(o->color_array);
            GX3DE_RENDER_KEY(o->volume_style);
            GX3DE_RENDER_KEY(o->projection_source);GX3DE_RENDER_KEY(o->projection_plane);
            for(const auto* texture:o->planar_textures){
                GX3DE_RENDER_KEY(texture);
                GX3DE_RENDER_KEY(texture->spec);
                const auto* image=texture->image.get();GX3DE_RENDER_KEY(image);
            }
            for(const auto* texture:o->curved_textures){
                GX3DE_RENDER_KEY(texture);GX3DE_RENDER_KEY(texture->spec);
                const auto* image=texture->image.get();GX3DE_RENDER_KEY(image);
                GX3DE_RENDER_KEY(texture->gizmo_visible);
            }
            if(o->scientific){const auto mtime=o->scientific->dataset->GetMTime();
                GX3DE_RENDER_KEY(mtime);}
        }
        for(const auto* r:s->repeats){GX3DE_RENDER_KEY(r);GX3DE_RENDER_KEY(r->source);
            GX3DE_RENDER_KEY(r->source_world);GX3DE_RENDER_KEY(r->visible);
            GX3DE_RENDER_KEY(r->opacity);GX3DE_RENDER_KEY(r->presentation_enabled);}
        for(const auto* marker:s->markers){GX3DE_RENDER_KEY(marker);
            GX3DE_RENDER_KEY(marker->view);GX3DE_RENDER_KEY(marker->anchor);
            GX3DE_RENDER_KEY(marker->style);}
        for(const auto* section:s->sections){GX3DE_RENDER_KEY(section);
            GX3DE_RENDER_KEY(section->style);}
        for(const auto* profile:s->profiles){GX3DE_RENDER_KEY(profile);
            GX3DE_RENDER_KEY(profile->style);}
        for(const auto* measurement:s->measurements){GX3DE_RENDER_KEY(measurement);
            GX3DE_RENDER_KEY(measurement->style);}
        for(const auto* gizmo:v->gizmos){GX3DE_RENDER_KEY(gizmo);
            GX3DE_RENDER_KEY(gizmo->spec);GX3DE_RENDER_KEY(gizmo->hover);
            GX3DE_RENDER_KEY(gizmo->active);}
    }
#undef GX3DE_RENDER_KEY
    return key;
}
static gx3de_result renderer_capture(gx3de_target* target,uint64_t bytes) {
    // VTK depth peeling and a multisampled render FBO cannot be combined.
    // Preserve requested MSAA for opaque scenes; use peeling for translucent
    // props and report the effective sample policy instead of dropping them.
    bool peeling=false;
    if(target->quality.transparency_mode==GX3DE_TRANSPARENCY_DEPTH_PEEL)
        for(auto& rv:target->rendered){auto* props=rv.renderer->GetViewProps();props->InitTraversal();while(auto* prop=props->GetNextProp())if(prop->HasTranslucentPolygonalGeometry()){peeling=true;break;}}
    target->window->SetMultiSamples(peeling?0:int(target->quality.msaa_samples));
    target->window->Render();
    std::string msaa_report=peeling&&target->quality.msaa_samples?"GX3DE depth peeling active; effective MSAA 0 (requested MSAA retained for opaque scenes)\n":"";
    if(target->quality.msaa_samples&&!peeling){
        /* VTK rasterizes into RenderFramebuffer, then resolves/blits to the
         * caller's window. GL_SAMPLES on the post-Render default framebuffer
         * describes that host window, not the scene's MSAA target. */
        auto* window=vtkOpenGLRenderWindow::SafeDownCast(target->window);
        auto* render_fbo=window?window->GetRenderFramebuffer():nullptr;
        if(!render_fbo){
            target->diagnostic="requested MSAA "+std::to_string(target->quality.msaa_samples)+
                "x is unavailable; OpenGL render framebuffer was not created";
            target->rgba.clear();return GX3DE_UNSUPPORTED;
        }
        window->MakeCurrent();
        GLint max_samples=0;
        glGetIntegerv(GL_MAX_SAMPLES,&max_samples);
        render_fbo->SaveCurrentBindingsAndBuffers();
        render_fbo->Bind();
        GLint actual=0;
        glGetIntegerv(GL_SAMPLES,&actual);
        render_fbo->RestorePreviousBindingsAndBuffers();
        GLint previous_draw=0,previous_read=0,host_samples=0;
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&previous_draw);
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&previous_read);
        glBindFramebuffer(GL_FRAMEBUFFER,0);
        glGetIntegerv(GL_SAMPLES,&host_samples);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER,GLuint(previous_draw));
        glBindFramebuffer(GL_READ_FRAMEBUFFER,GLuint(previous_read));
        if(actual<int(target->quality.msaa_samples)){
            target->diagnostic="requested MSAA "+std::to_string(target->quality.msaa_samples)+
                "x is unavailable on the VTK render framebuffer ("+
                std::to_string(actual)+" samples); OpenGL GL_MAX_SAMPLES="+
                std::to_string(max_samples)+"; host/default framebuffer="+
                std::to_string(host_samples)+" samples";
            target->rgba.clear();return GX3DE_UNSUPPORTED;}
        msaa_report="GX3DE MSAA requested "+std::to_string(target->quality.msaa_samples)+
            "x; effective render framebuffer "+std::to_string(actual)+
            " samples; host/default framebuffer "+std::to_string(host_samples)+
            " samples; OpenGL GL_MAX_SAMPLES="+std::to_string(max_samples)+
            "; resolved to display\n";
    }
    vtkNew<vtkWindowToImageFilter> capture;capture->SetInput(target->window);
    capture->SetInputBufferTypeToRGBA();capture->ReadFrontBufferOff();capture->Update();
    auto* image=capture->GetOutput();if(!image||image->GetNumberOfScalarComponents()!=4||
       image->GetDimensions()[0]!=int(target->width)||image->GetDimensions()[1]!=int(target->height))
        return GX3DE_DEGENERATE;
    const auto* source=static_cast<const uint8_t*>(image->GetScalarPointer());
    if(!source)return GX3DE_DEGENERATE;
    target->rgba.resize(static_cast<size_t>(bytes));
    const size_t stride=static_cast<size_t>(target->width)*4;
    for(uint32_t y=0;y<target->height;++y)
        std::memcpy(target->rgba.data()+size_t(y)*stride,
            source+size_t(target->height-1-y)*stride,stride);
    const char* capabilities=target->window->ReportCapabilities();
    target->diagnostic=msaa_report;
    if(capabilities)target->diagnostic.append(capabilities,
        std::min<size_t>(std::strlen(capabilities),4096));
    return GX3DE_OK;
}
static uint64_t renderer_sat_add(uint64_t a,uint64_t b){
    return b>UINT64_MAX-a?UINT64_MAX:a+b;
}
static uint64_t renderer_sat_mul(uint64_t a,uint64_t b){
    return a&&b>UINT64_MAX/a?UINT64_MAX:a*b;
}
/* Conservative planned-upload estimate, not a VRAM measurement. Count each
 * viewport separately because backends may not share its device geometry. */
static uint64_t renderer_gpu_estimate(gx3de_target* target){
    const uint64_t pixels=uint64_t(target->width)*target->height;
    const uint64_t samples=target->quality.msaa_samples?target->quality.msaa_samples:1;
    const uint64_t peel=target->quality.transparency_mode==GX3DE_TRANSPARENCY_DEPTH_PEEL?2:0;
    uint64_t bytes=renderer_sat_mul(pixels,8*(samples+peel));
    for(auto* vp:target->viewports){
        bytes=renderer_sat_add(bytes,4ull*1024*1024); /* overlays, mappers and transient buffers */
        if(vp->view->scene->shadows_enabled&&
           target->engine->graphics.shadow_policy!=GX3DE_SHADOW_OFF)
            bytes=renderer_sat_add(bytes,renderer_sat_mul(
                vp->view->lighting.light_count+vp->view->scene->scientific_lights.size(),
                (vp->view->scene->scientific_lights.size()>4?1024ull:2048ull)*
                (vp->view->scene->scientific_lights.size()>4?1024ull:2048ull)*8));
        for(auto* object:vp->view->scene->objects){
            if(!object->visible||object->opacity<=0)continue;
            if(object->mesh){
                bytes=renderer_sat_add(bytes,renderer_sat_mul(object->mesh->vertices.size(),48));
                bytes=renderer_sat_add(bytes,renderer_sat_mul(object->mesh->triangles.size(),4));
                for(const auto* assignment:object->planar_textures){
                    bytes=renderer_sat_add(bytes,renderer_sat_mul(
                        renderer_sat_mul(assignment->image->width,
                                         assignment->image->height),
                        assignment->image->channels));
                    bytes=renderer_sat_add(bytes,renderer_sat_mul(
                        assignment->patch->GetNumberOfPoints(),40));
                }
                for(const auto* assignment:object->curved_textures){
                    bytes=renderer_sat_add(bytes,renderer_sat_mul(
                        renderer_sat_mul(assignment->image->width,assignment->image->height),
                        assignment->image->channels));
                    bytes=renderer_sat_add(bytes,renderer_sat_mul(
                        assignment->patch->GetNumberOfPoints(),40));
                }
            }
#ifdef GX3DE_WITH_OCCT
            else if(object->brep)bytes=renderer_sat_add(bytes,256ull*1024*1024);
#endif
            else if(object->scientific){
                const auto kib=uint64_t(object->scientific->dataset->GetActualMemorySize());
                bytes=renderer_sat_add(bytes,renderer_sat_mul(kib,4096));
                if(object->presentation.sphere_glyphs)
                    bytes=renderer_sat_add(bytes,renderer_sat_mul(
                        std::min<uint64_t>(object->scientific->dataset->GetNumberOfPoints(),100000),4096));
                if(object->presentation.show_vectors)
                    bytes=renderer_sat_add(bytes,renderer_sat_mul(
                        std::min<uint64_t>(object->presentation.max_vector_glyphs,20000),1024));
            }
        }
        for(auto* repeat:vp->view->scene->repeats)if(repeat->presentation_enabled){
            bytes=renderer_sat_add(bytes,renderer_sat_mul(repeat->data.prototype.vertices.size(),48));
            bytes=renderer_sat_add(bytes,renderer_sat_mul(repeat->data.prototype.triangles.size(),4));
            bytes=renderer_sat_add(bytes,renderer_sat_mul(repeat->data.matches.size(),128));
        }
        for(const auto* cloud:vp->view->scene->particle_clouds)
            if(cloud->visible&&cloud->style.opacity>0)
                bytes=renderer_sat_add(bytes,renderer_sat_mul(cloud->particles.size(),12*32+20*3*8));
    }
    return bytes;
}
#include "native_3d_d3d11_renderer_impl.inc"
// Generic native scientific figure: calibrated box axes track the native camera.
// Presentation props are view-owned; camera/toggle updates retain scientific actors.
static void renderer_scientific_figure(gx3de_target* target,gx3de_render_viewport& rv) {
    const auto* vp=rv.viewport;const auto& f=vp->view->figure;
    if(!f.enabled){
        if(rv.figure_renderer){
            target->window->RemoveRenderer(rv.figure_renderer);rv.figure_renderer=nullptr;rv.scientific_axes=nullptr;
            rv.renderer->SetLayer(0);rv.renderer->SetBackgroundAlpha(0.0);
            const double W=target->width,H=target->height;
            rv.renderer->SetViewport(vp->x/W,1-(vp->y+vp->height)/H,(vp->x+vp->width)/W,1-vp->y/H);
        }
        return;
    }
    const double W=target->width,H=target->height;
    double sx,sy,sw,sh;figure_rect(vp->view,sx,sy,sw,sh);
    rv.renderer->SetBackgroundAlpha(1.0);rv.renderer->SetLayer(1);
    rv.renderer->SetViewport((vp->x+sx*vp->width)/W,
        1-(vp->y+(1-sy)*vp->height)/H,
        (vp->x+(sx+sw)*vp->width)/W,1-(vp->y+(1-sy-sh)*vp->height)/H);
    const auto bg=vp->view->background.bottom;
    const double ink=(.2126*bg.r+.7152*bg.g+.0722*bg.b)>.45?.12:.94;
    const double grid=ink>.5?.42:.68;
    const double scale=std::max(.8,std::min(double(vp->width)/900,double(vp->height)/640));
    if(!rv.figure_renderer){rv.figure_renderer=vtkSmartPointer<vtkRenderer>::New();
        rv.figure_renderer->SetLayer(0);rv.figure_renderer->InteractiveOff();
        target->window->AddRenderer(rv.figure_renderer);}
    auto* fr=rv.figure_renderer.GetPointer();fr->RemoveAllViewProps();
    fr->SetViewport(vp->x/W,1-(vp->y+vp->height)/H,(vp->x+vp->width)/W,1-vp->y/H);
    fr->SetBackground(bg.r,bg.g,bg.b);fr->SetBackgroundAlpha(1.0);
    // An uncropped figure camera has exactly the scene's world/pixel mapping.
    // Expand its frustum and translate its window center, preserving native pose.
    auto* fc=fr->GetActiveCamera();fc->DeepCopy(rv.renderer->GetActiveCamera());
    fc->SetParallelScale(fc->GetParallelScale()/sh);
    fc->SetViewAngle(2*std::atan(std::tan(fc->GetViewAngle()*3.141592653589793/360)/sh)*180/3.141592653589793);
    fc->SetWindowCenter(1-2*(sx+sw/2),1-2*(sy+sh/2));

    if(!rv.scientific_axes){
        rv.scientific_axes=vtkSmartPointer<vtkCubeAxesActor>::New();
        auto* a=rv.scientific_axes.GetPointer();
        a->SetBounds(f.world_bounds.min.x,f.world_bounds.max.x,
            f.world_bounds.min.y,f.world_bounds.max.y,f.world_bounds.min.z,f.world_bounds.max.z);
        a->SetXAxisRange(f.axis_min[0],f.axis_max[0]);
        a->SetYAxisRange(f.axis_min[1],f.axis_max[1]);
        a->SetZAxisRange(f.axis_min[2],f.axis_max[2]);
        a->SetXTitle(f.axis_labels_utf8[0]);a->SetYTitle(f.axis_labels_utf8[1]);a->SetZTitle(f.axis_labels_utf8[2]);
        a->SetCamera(fc);a->SetFlyModeToOuterEdges();
        a->SetUseTextActor3D(false);a->GetProperty()->SetColor(ink,ink,ink);
        a->SetGridLineLocation(vtkCubeAxesActor::VTK_GRID_LINES_FURTHEST);
        a->SetDrawXGridlines(true);a->SetDrawYGridlines(true);a->SetDrawZGridlines(true);
        a->XAxisMinorTickVisibilityOff();a->YAxisMinorTickVisibilityOff();a->ZAxisMinorTickVisibilityOff();
        a->SetTickLocationToOutside();a->SetScreenSize(12*scale);
        a->SetLabelOffset(8*scale);double offset[2]={28*scale,28*scale};a->SetTitleOffset(offset);
        a->SetXLabelFormat("%.5g");a->SetYLabelFormat("%.5g");a->SetZLabelFormat("%.5g");
        a->GetXAxesLinesProperty()->SetColor(ink,ink,ink);
        a->GetYAxesLinesProperty()->SetColor(ink,ink,ink);
        a->GetZAxesLinesProperty()->SetColor(ink,ink,ink);
        a->GetXAxesGridlinesProperty()->SetColor(grid,grid,grid);
        a->GetYAxesGridlinesProperty()->SetColor(grid,grid,grid);
        a->GetZAxesGridlinesProperty()->SetColor(grid,grid,grid);
        for(int i=0;i<3;++i){a->GetTitleTextProperty(i)->SetColor(ink,ink,ink);
            a->GetLabelTextProperty(i)->SetColor(ink,ink,ink);
            a->GetTitleTextProperty(i)->ShadowOff();a->GetLabelTextProperty(i)->ShadowOff();
            a->GetTitleTextProperty(i)->BoldOff();a->GetLabelTextProperty(i)->BoldOff();}
        a->PickableOff();
    }
    auto* calibrated=rv.scientific_axes.GetPointer();
    calibrated->SetBounds(f.world_bounds.min.x,f.world_bounds.max.x,f.world_bounds.min.y,f.world_bounds.max.y,f.world_bounds.min.z,f.world_bounds.max.z);
    calibrated->SetXAxisRange(f.axis_min[0],f.axis_max[0]);calibrated->SetYAxisRange(f.axis_min[1],f.axis_max[1]);calibrated->SetZAxisRange(f.axis_min[2],f.axis_max[2]);
    calibrated->SetXTitle(f.axis_labels_utf8[0]);calibrated->SetYTitle(f.axis_labels_utf8[1]);calibrated->SetZTitle(f.axis_labels_utf8[2]);
    rv.scientific_axes->SetVisibility(f.axes_grid_visible);
    fr->AddActor(rv.scientific_axes);
    auto text=[&](const char* value,double x,double y,int size,bool rotate){
        if(!value||!value[0])return;
        vtkNew<vtkTextActor> t;t->SetInput(value);
        t->SetPosition(x*vp->width,y*vp->height);
        auto* p=t->GetTextProperty();p->SetColor(ink,ink,ink);p->SetFontSize(int(size*scale));
        p->ShadowOff();p->BoldOff();p->ItalicOff();p->SetFontFamilyToArial();p->SetJustificationToCentered();p->SetVerticalJustificationToCentered();
        if(rotate)p->SetOrientation(90);
        fr->AddActor2D(t);
    };
    text(f.title_utf8,.45,.95,18,false);text(f.legend_utf8,.45,.035,12,false);
    if(f.colorbar_visible){
        vtkNew<vtkLookupTable> lut;lut->SetNumberOfTableValues(f.palette_count);
        lut->SetRange(f.scalar_min,f.scalar_max);lut->Build();
        for(uint32_t i=0;i<f.palette_count;++i){const auto rgb=f.palette[i];lut->SetTableValue(i,rgb.r,rgb.g,rgb.b,1);}
        vtkNew<vtkScalarBarActor> bar;bar->SetLookupTable(lut);bar->SetTitle("");
        bar->SetPosition(.84,.20);bar->SetWidth(.10);bar->SetHeight(.57);
        bar->SetNumberOfLabels(6);bar->SetLabelFormat("%.5g");bar->SetMaximumNumberOfColors(f.palette_count);
        bar->GetLabelTextProperty()->SetColor(ink,ink,ink);bar->GetLabelTextProperty()->ShadowOff();bar->GetLabelTextProperty()->BoldOff();bar->GetLabelTextProperty()->ItalicOff();bar->GetLabelTextProperty()->SetFontSize(int(14*scale));
        bar->UnconstrainedFontSizeOn();bar->SetBarRatio(.30);bar->SetTextPad(int(5*scale));
        fr->AddActor2D(bar);text(f.scalar_label_utf8,.974,.485,14,true);
    }
}
static gx3de_result renderer_rebuild(gx3de_target* target) {
    if(!target)return GX3DE_INVALID_ARGUMENT;
    if(std::this_thread::get_id()!=target->render_owner){
        target->diagnostic="render target used from a non-owner thread";
        target->rgba.clear();return GX3DE_UNSUPPORTED;}
    target->diagnostic.clear();
    // A failed attempt never leaves pixels from a prior successful frame
    // readable as though they represented the current scene/view state.
    target->rgba.clear();
    const uint64_t bytes=uint64_t(target->width)*target->height*4;
    if(bytes>256ull*1024*1024||target->width>16384||target->height>16384){
        target->diagnostic="target RGBA pixel budget exceeded (256 MiB / 16384 per axis)";
        return GX3DE_RANGE;}
    target->gpu_estimated_bytes=renderer_gpu_estimate(target);
    if(target->gpu_budget_bytes&&target->gpu_estimated_bytes>target->gpu_budget_bytes){
        target->gpu_last_rejected_bytes=target->gpu_estimated_bytes;
        target->diagnostic="estimated GPU resource use "+std::to_string(target->gpu_estimated_bytes)+
            " bytes exceeds configured budget "+std::to_string(target->gpu_budget_bytes)+
            " bytes; exact driver allocation unavailable";
        return GX3DE_RANGE;
    }
    target->gpu_last_rejected_bytes=0;
    if(target->backend_preference==GX3DE_RENDER_BACKEND_D3D11){
        for(auto* vp:target->viewports)if(vp->view->figure.enabled){target->diagnostic="Scientific figure axes/scalar bar require the VTK Native3D backend";return GX3DE_UNSUPPORTED;}
        for(auto* vp:target->viewports)for(auto* o:vp->view->scene->objects)if(o->scientific&&o->color_array>=0){
            uint32_t assoc=0;scientific_array_by_index(*o->scientific,static_cast<uint64_t>(o->color_array),&assoc);
            if(assoc==GX3DE_SCI_ASSOC_CELL){target->diagnostic="Cell-associated direct RGB requires the VTK Native3D backend";return GX3DE_UNSUPPORTED;}}

#ifdef _WIN32
        const auto rc=gx3de_d3d_render(target);
        if(rc!=GX3DE_OK)target->rgba.clear();
        return rc;
#else
        target->diagnostic="D3D11 presentation requires Windows";
        return GX3DE_UNSUPPORTED;
#endif
    }
#if !defined(_WIN32)
    if(!std::getenv("DISPLAY")){target->diagnostic="X11 DISPLAY is unset";
        return GX3DE_UNSUPPORTED;}
    if(const char* indirect=std::getenv("LIBGL_ALWAYS_INDIRECT"))
        if(indirect[0]=='1'){target->diagnostic=
            "indirect GLX requested; use an isolated direct/Mesa renderer process";
            return GX3DE_UNSUPPORTED;}
#endif
    try{
        const std::string state_key=renderer_static_state_key(target);
        if(target->window&&!target->rendered.empty()&&
           target->render_key==state_key){
            for(auto& rv:target->rendered){const auto* vp=rv.viewport;
                auto* camera=rv.renderer->GetActiveCamera();const auto& c=vp->view->camera;
                camera->SetPosition(c.position.x,c.position.y,c.position.z);
                camera->SetFocalPoint(c.target.x,c.target.y,c.target.z);
                camera->SetViewUp(c.up.x,c.up.y,c.up.z);
                camera->SetViewAngle(c.vertical_fov_degrees);
                camera->SetClippingRange(c.near_clip,c.far_clip);
                camera->SetParallelProjection(c.orthographic);
                camera->SetParallelScale(vp->view->orthographic_height>0?
                    vp->view->orthographic_height*0.5:
                    length(sub(c.position,c.target))*
                    std::tan(c.vertical_fov_degrees*3.141592653589793/360.0));
                for(const auto& actor:rv.overlay_actors)rv.renderer->RemoveActor(actor);
                rv.overlay_actors.clear();
                rv.props.erase(std::remove_if(rv.props.begin(),rv.props.end(),
                    [](const gx3de_render_prop& prop){return prop.gizmo!=nullptr;}),
                    rv.props.end());
                const auto overlay_status=renderer_add_overlays(rv);
                if(overlay_status!=GX3DE_OK){target->render_key.clear();
                    target->diagnostic="overlay display budget exceeded";return overlay_status;}
                renderer_scientific_figure(target,rv);
                renderer_navcube(target,rv);
                renderer_orientation_indicator(target,rv);
            }
            auto rc=renderer_capture(target,bytes);
            if(rc!=GX3DE_OK)target->render_key.clear();
            else {++target->completed_frames;++target->geometry_reuse_frames;}
            return rc;
        }
        if(!target->window){target->window=vtkSmartPointer<vtkRenderWindow>::New();
            target->window->AlphaBitPlanesOn();target->window->SetNumberOfLayers(2);
            target->window->SetOffScreenRendering(target->native_kind?0:1);
            if(target->native_kind){const std::string id=std::to_string(target->native_id);
                target->window->SetWindowInfo(id.c_str());}}
        target->window->SetSize(int(target->width),int(target->height));
        target->window->SetMultiSamples(int(target->quality.msaa_samples));
        target->render_key.clear();
        for(auto& rv:target->rendered){target->window->RemoveRenderer(rv.renderer);
            if(rv.navcube_renderer)target->window->RemoveRenderer(rv.navcube_renderer);
            if(rv.orientation_renderer)target->window->RemoveRenderer(rv.orientation_renderer);
            if(rv.figure_renderer)target->window->RemoveRenderer(rv.figure_renderer);}
        target->rendered.clear();target->rendered.reserve(target->viewports.size());
        target->rgba.clear();
        uint64_t display_triangles=0;
        for(auto* viewport:target->viewports){gx3de_render_viewport rv{};rv.viewport=viewport;
            unsigned clipping_planes=viewport->view->clip_box.enabled?6u:0u;
            for(const auto& plane:viewport->view->clips)clipping_planes+=plane.enabled?1u:0u;
            if(clipping_planes>6){target->diagnostic=
                "VTK OpenGL supports at most 6 simultaneous clipping planes; disable planes or clip box";
                return GX3DE_UNSUPPORTED;}
            rv.renderer=viewport->view->scene->shadows_enabled&&
                target->engine->graphics.shadow_policy!=GX3DE_SHADOW_OFF?
                vtkSmartPointer<vtkRenderer>(vtkSmartPointer<gx3de_shadow_renderer>::New()):
                vtkSmartPointer<vtkRenderer>::New();
            const auto& graphics=target->engine->graphics;
            const uint32_t display_level=target->interaction_active&&graphics.interaction_lod_enabled?
                graphics.interaction_lod:graphics.normal_lod;
            if(display_level>=GX3DE_LOD_HIGH&&target->quality.msaa_samples==0)
                rv.renderer->UseFXAAOn();
            const double W=target->width,H=target->height;
            rv.renderer->SetViewport(viewport->x/W,1.0-(viewport->y+viewport->height)/H,
                                     (viewport->x+viewport->width)/W,1.0-viewport->y/H);
            const auto& bg=viewport->view->background;
            rv.renderer->SetBackground(bg.bottom.r,bg.bottom.g,bg.bottom.b);
            rv.renderer->SetBackground2(bg.top.r,bg.top.g,bg.top.b);
            rv.renderer->SetGradientBackground(bg.gradient!=0);
            renderer_checkerboard(rv);
            rv.renderer->SetUseDepthPeeling(target->quality.transparency_mode==
                                            GX3DE_TRANSPARENCY_DEPTH_PEEL);
            rv.renderer->SetMaximumNumberOfPeels(64);
            rv.renderer->SetOcclusionRatio(0.1);
            rv.renderer->AutomaticLightCreationOff();rv.renderer->RemoveAllLights();
            if(viewport->view->lighting.enabled){for(uint32_t li=0;li<viewport->view->lighting.light_count;++li){
                const auto& light=viewport->view->lighting.lights[li];vtkNew<vtkLight> vtk_light;
                vtk_light->SetLightTypeToSceneLight();vtk_light->SetPositional(false);
                vtk_light->SetPosition(-light.direction.x,-light.direction.y,-light.direction.z);
                vtk_light->SetFocalPoint(0,0,0);
                vtk_light->SetColor(light.color.r,light.color.g,light.color.b);
                vtk_light->SetShadowAttenuation((viewport->view->shadow_light_mask>>li)&1u);
                vtk_light->SetIntensity(light.intensity);
                const auto& point=viewport->view->positional_lights[li];
                if(point.enabled){vtk_light->SetPositional(true);
                    vtk_light->SetPosition(point.position.x,point.position.y,point.position.z);
                    vtk_light->SetFocalPoint(0,0,0);vtk_light->SetConeAngle(180);
                    vtk_light->SetColor(point.color.r,point.color.g,point.color.b);
                    vtk_light->SetIntensity(point.intensity);
                    vtk_light->SetAttenuationValues(point.attenuation_constant,
                        point.attenuation_linear,point.attenuation_quadratic);}
                rv.renderer->AddLight(vtk_light);}}
            for(const auto* source:viewport->view->scene->scientific_lights){
                const auto& s=source->spec;if(!s.enabled||s.intensity<=0)continue;
                const auto color=scientific_light_rgb(s.wavelength_nm);
                vtkNew<vtkLight> vtk_light;vtk_light->SetLightTypeToSceneLight();
                vtk_light->SetPositional(true);
                vtk_light->SetPosition(s.position.x,s.position.y,s.position.z);
                vtk_light->SetFocalPoint(s.position.x+s.direction.x,
                    s.position.y+s.direction.y,s.position.z+s.direction.z);
                vtk_light->SetConeAngle(s.cone_angle_degrees);
                vtk_light->SetExponent(s.falloff_exponent);
                vtk_light->SetColor(color.r,color.g,color.b);
                vtk_light->SetIntensity(std::min(s.intensity,10.0));
                vtk_light->SetAttenuationValues(s.attenuation_constant,
                    s.attenuation_linear,s.attenuation_quadratic);
                vtk_light->SetShadowAttenuation(s.shadows_enabled?1.0:0.0);
                rv.renderer->AddLight(vtk_light);
            }
            auto* camera=rv.renderer->GetActiveCamera();const auto& c=viewport->view->camera;
            camera->SetPosition(c.position.x,c.position.y,c.position.z);
            camera->SetFocalPoint(c.target.x,c.target.y,c.target.z);
            camera->SetViewUp(c.up.x,c.up.y,c.up.z);
            camera->SetViewAngle(c.vertical_fov_degrees);
            camera->SetClippingRange(c.near_clip,c.far_clip);
            camera->SetParallelProjection(c.orthographic);
            camera->SetParallelScale(viewport->view->orthographic_height>0?
                viewport->view->orthographic_height*0.5:
                length(sub(c.position,c.target))*
                std::tan(c.vertical_fov_degrees*3.141592653589793/360.0));
            for(auto* object:viewport->view->scene->objects){
                if(!object->visible||object->opacity<=0)continue;
                bool replaced=false;for(auto* repeat:viewport->view->scene->repeats)
                    if(repeat->presentation_enabled&&repeat->source==object){replaced=true;break;}
                if(replaced)continue;
                if(object->mesh){std::string lod_error;
                    const Mesh* mesh=renderer_display_mesh(target,object,lod_error);
                    if(!mesh){target->diagnostic="display LOD derivation failed: "+lod_error;
                        return GX3DE_DEGENERATE;}
                    display_triangles+=mesh->triangles.size()/3;
                    if(display_triangles>target->engine->graphics.display_triangle_budget){target->diagnostic=
                        "configured display triangle budget exceeded";return GX3DE_RANGE;}
                    const auto& policy=target->engine->graphics;
                    const uint32_t level=target->interaction_active&&policy.interaction_lod_enabled?
                        policy.interaction_lod:policy.normal_lod;
                    auto poly=renderer_mesh_poly(*mesh,level>=GX3DE_LOD_HIGH);
                    renderer_add_prop(rv,object,GX3DE_PICK_MESH,poly,world(object),viewport->view);
                    renderer_add_planar_textures(rv,object,world(object),viewport->view);
                    rv.props.back().derived_lod=mesh!=object->mesh.get();}
#ifdef GX3DE_WITH_OCCT
                else if(object->brep){std::string error;
                    const Mesh* mesh=renderer_brep_display_mesh(target,object,error);
                    if(!mesh){
                        target->diagnostic="B-Rep display tessellation failed: "+error;
                        return GX3DE_DEGENERATE;}
                    display_triangles+=mesh->triangles.size()/3;if(display_triangles>target->engine->graphics.display_triangle_budget){
                        target->diagnostic="configured display triangle budget exceeded";return GX3DE_RANGE;}
                    const auto& policy=target->engine->graphics;
                    const uint32_t level=target->interaction_active&&policy.interaction_lod_enabled?
                        policy.interaction_lod:policy.normal_lod;
                    auto poly=renderer_mesh_poly(*mesh,level>=GX3DE_LOD_HIGH);
                    renderer_add_prop(rv,object,GX3DE_PICK_BREP_DISPLAY,poly,world(object),viewport->view);}
#endif
                else if(object->scientific){auto rc=renderer_add_scientific(rv,object,
                    display_triangles,target->engine->graphics.display_triangle_budget);
                    if(rc!=GX3DE_OK){target->diagnostic=rc==GX3DE_RANGE?
                        "scientific display budget exceeded (1M input points/cells, 150k tube points, 100k sphere glyphs subject to triangle budget)":
                        "scientific display data or vector sampling failed";
                        return rc;}}
            }
            for(auto* cloud:viewport->view->scene->particle_clouds){
                if(!cloud->visible||cloud->style.opacity<=0)continue;
                if(cloud->particles.size()>(target->engine->graphics.display_triangle_budget-display_triangles)/20){
                    target->diagnostic="configured display triangle budget exceeded by particle cloud";
                    return GX3DE_RANGE;}
                display_triangles+=cloud->particles.size()*20;
                renderer_add_cloud(rv,cloud);
            }
            renderer_add_scientific_beams(rv);
            auto repeat_status=renderer_add_repeats(rv,display_triangles,
                target->engine->graphics.display_triangle_budget);
            if(repeat_status!=GX3DE_OK){target->diagnostic="repeated-component display budget exceeded";
                return repeat_status;}
            auto overlay_status=renderer_add_overlays(rv);
            if(overlay_status!=GX3DE_OK){target->diagnostic="overlay display budget exceeded";
                return overlay_status;}
            renderer_scientific_figure(target,rv);
            target->window->AddRenderer(rv.renderer);target->rendered.push_back(std::move(rv));
            renderer_navcube(target,target->rendered.back());
            renderer_orientation_indicator(target,target->rendered.back());
            if(viewport->view->scene->shadows_enabled&&
               target->engine->graphics.shadow_policy!=GX3DE_SHADOW_OFF)
                gx3de_shadow_renderer::SafeDownCast(target->rendered.back().renderer)
                    ->Configure(&target->rendered.back());
        }
        auto rc=renderer_capture(target,bytes);
        if(rc==GX3DE_OK){target->render_key=state_key;
            ++target->completed_frames;++target->geometry_rebuild_frames;}
        else target->render_key.clear();
        return rc;
    }catch(const std::bad_alloc&){target->rgba.clear();target->diagnostic="render out of memory";
        return GX3DE_OUT_OF_MEMORY;
    }catch(const std::exception& e){target->rgba.clear();target->diagnostic=e.what();
        return GX3DE_DEGENERATE;}
}
