// SPDX-License-Identifier: GPL-3.0-or-later
// Windows-only D3D11 presentation. Geometry is submitted directly to D3D11;
// VTK is used only for CPU scientific surface extraction and B-Rep tessellation.
#ifdef _WIN32
using Microsoft::WRL::ComPtr;
struct gx3de_d3d_vertex {float position[4],color[4];};
struct gx3de_d3d_state {
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    ComPtr<IDXGISwapChain> swapchain;
    ComPtr<ID3D11Texture2D> color,depth,staging;
    ComPtr<ID3D11RenderTargetView> rtv;
    ComPtr<ID3D11DepthStencilView> dsv;
    ComPtr<ID3D11VertexShader> vs;
    ComPtr<ID3D11PixelShader> ps;
    ComPtr<ID3D11InputLayout> layout;
    ComPtr<ID3D11RasterizerState> raster;
    ComPtr<ID3D11BlendState> blend;
    uint32_t width=0,height=0;
    std::string adapter;
};
static std::string gx3de_d3d_error(const char* where,HRESULT hr) {
    char code[32];std::snprintf(code,sizeof code,"0x%08lX",static_cast<unsigned long>(hr));
    return std::string(where)+" failed: HRESULT "+code;
}
static bool gx3de_d3d_targets(gx3de_d3d_state& s,gx3de_target* t) {
    s.context->OMSetRenderTargets(0,nullptr,nullptr);
    s.rtv.Reset();s.dsv.Reset();s.color.Reset();s.depth.Reset();s.staging.Reset();
    D3D11_TEXTURE2D_DESC desc{};desc.Width=t->width;desc.Height=t->height;
    desc.MipLevels=1;desc.ArraySize=1;desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count=1;desc.Usage=D3D11_USAGE_DEFAULT;
    desc.BindFlags=D3D11_BIND_RENDER_TARGET;
    HRESULT hr=s.device->CreateTexture2D(&desc,nullptr,s.color.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 color target",hr);return false;}
    hr=s.device->CreateRenderTargetView(s.color.Get(),nullptr,s.rtv.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 color view",hr);return false;}
    desc.Format=DXGI_FORMAT_D24_UNORM_S8_UINT;desc.BindFlags=D3D11_BIND_DEPTH_STENCIL;
    hr=s.device->CreateTexture2D(&desc,nullptr,s.depth.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 depth target",hr);return false;}
    hr=s.device->CreateDepthStencilView(s.depth.Get(),nullptr,s.dsv.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 depth view",hr);return false;}
    desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;desc.BindFlags=0;
    desc.Usage=D3D11_USAGE_STAGING;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
    hr=s.device->CreateTexture2D(&desc,nullptr,s.staging.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 RGBA staging target",hr);return false;}
    if(s.swapchain) {
        hr=s.swapchain->ResizeBuffers(0,t->width,t->height,DXGI_FORMAT_UNKNOWN,0);
        if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("DXGI swap-chain resize",hr);return false;}
    }
    s.width=t->width;s.height=t->height;return true;
}
static bool gx3de_d3d_initialize(gx3de_d3d_state& s,gx3de_target* t) {
    const D3D_FEATURE_LEVEL levels[]={D3D_FEATURE_LEVEL_11_1,D3D_FEATURE_LEVEL_11_0};
    D3D_FEATURE_LEVEL selected{};
    HRESULT hr=D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,
        levels,2,D3D11_SDK_VERSION,s.device.GetAddressOf(),&selected,s.context.GetAddressOf());
    if(hr==E_INVALIDARG)hr=D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,
        levels+1,1,D3D11_SDK_VERSION,s.device.GetAddressOf(),&selected,s.context.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 hardware device/context",hr);return false;}
    ComPtr<IDXGIDevice> dxgiDevice;ComPtr<IDXGIAdapter> adapter;
    if(SUCCEEDED(s.device.As(&dxgiDevice))&&SUCCEEDED(dxgiDevice->GetAdapter(adapter.GetAddressOf()))) {
        DXGI_ADAPTER_DESC info{};if(SUCCEEDED(adapter->GetDesc(&info))) {
            char buffer[256]{};WideCharToMultiByte(CP_UTF8,0,info.Description,-1,buffer,sizeof buffer,nullptr,nullptr);
            s.adapter=buffer;
        }
    }
    if(t->native_kind==GX3DE_NATIVE_WINDOW_WIN32) {
        ComPtr<IDXGIFactory> factory;
        if(!adapter||FAILED(adapter->GetParent(IID_PPV_ARGS(factory.GetAddressOf())))) {
            t->diagnostic="DXGI adapter factory unavailable";return false;
        }
        DXGI_SWAP_CHAIN_DESC swap{};swap.BufferDesc.Width=t->width;swap.BufferDesc.Height=t->height;
        swap.BufferDesc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;swap.SampleDesc.Count=1;
        swap.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;swap.BufferCount=2;
        swap.OutputWindow=reinterpret_cast<HWND>(static_cast<uintptr_t>(t->native_id));
        swap.Windowed=TRUE;swap.SwapEffect=DXGI_SWAP_EFFECT_DISCARD;
        hr=factory->CreateSwapChain(s.device.Get(),&swap,s.swapchain.GetAddressOf());
        if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("DXGI native swap chain",hr);return false;}
    }
    static constexpr char shader[]=
        "struct V {float4 position:POSITION;float4 color:COLOR;};"
        "struct O {float4 position:SV_POSITION;float4 color:COLOR;};"
        "O vs_main(V input){O o;o.position=input.position;o.color=input.color;return o;}"
        "float4 ps_main(O input):SV_TARGET{return input.color;}";
    ComPtr<ID3DBlob> vsBytecode,psBytecode,errors;
    hr=D3DCompile(shader,sizeof(shader)-1,nullptr,nullptr,nullptr,"vs_main","vs_4_0",0,0,
        vsBytecode.GetAddressOf(),errors.GetAddressOf());
    if(FAILED(hr)){t->diagnostic="D3D11 vertex shader compilation failed";return false;}
    errors.Reset();
    hr=D3DCompile(shader,sizeof(shader)-1,nullptr,nullptr,nullptr,"ps_main","ps_4_0",0,0,
        psBytecode.GetAddressOf(),errors.GetAddressOf());
    if(FAILED(hr)){t->diagnostic="D3D11 pixel shader compilation failed";return false;}
    hr=s.device->CreateVertexShader(vsBytecode->GetBufferPointer(),vsBytecode->GetBufferSize(),
        nullptr,s.vs.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 vertex shader",hr);return false;}
    hr=s.device->CreatePixelShader(psBytecode->GetBufferPointer(),psBytecode->GetBufferSize(),
        nullptr,s.ps.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 pixel shader",hr);return false;}
    D3D11_INPUT_ELEMENT_DESC elements[]={{"POSITION",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,0,
        D3D11_INPUT_PER_VERTEX_DATA,0},{"COLOR",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,16,
        D3D11_INPUT_PER_VERTEX_DATA,0}};
    hr=s.device->CreateInputLayout(elements,2,vsBytecode->GetBufferPointer(),
        vsBytecode->GetBufferSize(),s.layout.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 input layout",hr);return false;}
    D3D11_RASTERIZER_DESC raster{};raster.FillMode=D3D11_FILL_SOLID;
    raster.CullMode=D3D11_CULL_NONE;raster.DepthClipEnable=TRUE;
    hr=s.device->CreateRasterizerState(&raster,s.raster.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 raster state",hr);return false;}
    D3D11_BLEND_DESC blend{};auto& b=blend.RenderTarget[0];b.BlendEnable=TRUE;
    b.SrcBlend=D3D11_BLEND_SRC_ALPHA;b.DestBlend=D3D11_BLEND_INV_SRC_ALPHA;
    b.BlendOp=D3D11_BLEND_OP_ADD;b.SrcBlendAlpha=D3D11_BLEND_ONE;
    b.DestBlendAlpha=D3D11_BLEND_ZERO;b.BlendOpAlpha=D3D11_BLEND_OP_ADD;
    b.RenderTargetWriteMask=D3D11_COLOR_WRITE_ENABLE_ALL;
    hr=s.device->CreateBlendState(&blend,s.blend.GetAddressOf());
    if(FAILED(hr)){t->diagnostic=gx3de_d3d_error("D3D11 blend state",hr);return false;}
    return gx3de_d3d_targets(s,t);
}
static gx3de_d3d_vertex gx3de_d3d_project(gx3de_vec3 point,const gx3de_mat4& pose,
    const gx3de_camera& camera,double aspect,double orthoHalfHeight,
    gx3de_rgb color,double alpha) {
    const auto p=apply(pose,point),d=sub(p,camera.position);
    const auto forward=mul(sub(camera.target,camera.position),
        1.0/length(sub(camera.target,camera.position)));
    const auto right=mul(cross(forward,camera.up),1.0/length(cross(forward,camera.up)));
    const auto up=cross(right,forward);
    const double x=dot(d,right),y=dot(d,up),z=dot(d,forward);
    gx3de_d3d_vertex v{};
    if(camera.orthographic) {
        v.position[0]=float(x/(orthoHalfHeight*aspect));
        v.position[1]=float(y/orthoHalfHeight);
        v.position[2]=float((z-camera.near_clip)/(camera.far_clip-camera.near_clip));
        v.position[3]=1;
    } else {
        const double scale=1.0/std::tan(camera.vertical_fov_degrees*3.141592653589793/360.0);
        v.position[0]=float(x*scale/aspect);v.position[1]=float(y*scale);
        v.position[2]=float((camera.far_clip*z-camera.near_clip*camera.far_clip)/
            (camera.far_clip-camera.near_clip));v.position[3]=float(z);
    }
    v.color[0]=float(color.r);v.color[1]=float(color.g);v.color[2]=float(color.b);
    v.color[3]=float(alpha);return v;
}
static gx3de_result gx3de_d3d_draw(gx3de_d3d_state& s,gx3de_target* target,
    gx3de_viewport* viewport,gx3de_object* object,const Mesh& mesh) {
    if(mesh.vertices.empty())return GX3DE_OK;
    const double aspect=double(viewport->width)/viewport->height;
    const auto pose=world(object);const auto& camera=viewport->view->camera;
    const double orthoHalfHeight=viewport->view->orthographic_height>0?
        viewport->view->orthographic_height*0.5:
        length(sub(camera.position,camera.target))*
        std::tan(camera.vertical_fov_degrees*3.141592653589793/360.0);
    std::vector<gx3de_d3d_vertex> vertices;
    if(!mesh.triangles.empty()) {
        if(mesh.triangles.size()>12000000)return GX3DE_RANGE;
        vertices.reserve(mesh.triangles.size());
        for(uint32_t index:mesh.triangles) {
            if(index>=mesh.vertices.size())return GX3DE_DEGENERATE;
            vertices.push_back(gx3de_d3d_project(mesh.vertices[index],pose,camera,aspect,orthoHalfHeight,
                object->style.color,object->opacity));
        }
    } else {
        if(mesh.vertices.size()>1000000)return GX3DE_RANGE;
        vertices.reserve(mesh.vertices.size());
        for(const auto& p:mesh.vertices)vertices.push_back(gx3de_d3d_project(p,pose,camera,
            aspect,orthoHalfHeight,object->style.color,object->opacity));
    }
    if(vertices.empty())return GX3DE_OK;
    D3D11_BUFFER_DESC desc{};desc.ByteWidth=UINT(vertices.size()*sizeof(gx3de_d3d_vertex));
    desc.Usage=D3D11_USAGE_IMMUTABLE;desc.BindFlags=D3D11_BIND_VERTEX_BUFFER;
    D3D11_SUBRESOURCE_DATA data{};data.pSysMem=vertices.data();
    ComPtr<ID3D11Buffer> buffer;
    const HRESULT hr=s.device->CreateBuffer(&desc,&data,buffer.GetAddressOf());
    if(FAILED(hr)){target->diagnostic=gx3de_d3d_error("D3D11 geometry upload",hr);return GX3DE_OUT_OF_MEMORY;}
    UINT stride=sizeof(gx3de_d3d_vertex),offset=0;
    s.context->IASetVertexBuffers(0,1,buffer.GetAddressOf(),&stride,&offset);
    s.context->IASetPrimitiveTopology(mesh.triangles.empty()?D3D11_PRIMITIVE_TOPOLOGY_POINTLIST:
        D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    s.context->Draw(UINT(vertices.size()),0);return GX3DE_OK;
}
static gx3de_result gx3de_d3d_render(gx3de_target* target) {
    try {
        auto state=std::static_pointer_cast<gx3de_d3d_state>(target->d3d_state);
        if(!state){state=std::make_shared<gx3de_d3d_state>();
            if(!gx3de_d3d_initialize(*state,target))return GX3DE_UNSUPPORTED;
            target->d3d_state=state;
        } else if(state->width!=target->width||state->height!=target->height) {
            if(!gx3de_d3d_targets(*state,target))return GX3DE_UNSUPPORTED;
        }
        auto& s=*state;
        s.context->OMSetRenderTargets(1,s.rtv.GetAddressOf(),s.dsv.Get());
        s.context->IASetInputLayout(s.layout.Get());s.context->VSSetShader(s.vs.Get(),nullptr,0);
        s.context->PSSetShader(s.ps.Get(),nullptr,0);s.context->RSSetState(s.raster.Get());
        const float blendFactor[4]={0,0,0,0};
        s.context->OMSetBlendState(s.blend.Get(),blendFactor,0xffffffff);
        const float bg[4]={float(target->viewports.empty()?0.08:
            target->viewports.front()->view->background.top.r),
            float(target->viewports.empty()?0.10:target->viewports.front()->view->background.top.g),
            float(target->viewports.empty()?0.14:target->viewports.front()->view->background.top.b),1};
        s.context->ClearRenderTargetView(s.rtv.Get(),bg);
        s.context->ClearDepthStencilView(s.dsv.Get(),D3D11_CLEAR_DEPTH|D3D11_CLEAR_STENCIL,1,0);
        uint64_t displayed_triangles=0;
        for(auto* vp:target->viewports) {
            D3D11_VIEWPORT viewport{};viewport.TopLeftX=float(vp->x);
            viewport.TopLeftY=float(target->height-vp->y-vp->height);
            viewport.Width=float(vp->width);viewport.Height=float(vp->height);
            viewport.MinDepth=0;viewport.MaxDepth=1;s.context->RSSetViewports(1,&viewport);
            for(auto* repeat:vp->view->scene->repeats)if(repeat->presentation_enabled){
                target->diagnostic="D3D11 repeated-component presentation is unavailable";
                return GX3DE_UNSUPPORTED;
            }
            for(auto* object:vp->view->scene->objects) {
                if(!object->visible||object->opacity<=0)continue;
                Mesh extracted;
                const Mesh* mesh=nullptr;
                if(object->mesh){std::string error;
                    mesh=renderer_display_mesh(target,object,error);
                    if(!mesh){target->diagnostic="D3D11 display LOD failed: "+error;
                        return GX3DE_DEGENERATE;}}
#ifdef GX3DE_WITH_OCCT
                else if(object->brep) {std::string error;
                    mesh=renderer_brep_display_mesh(target,object,error);
                    if(!mesh) {
                        target->diagnostic="D3D11 B-Rep tessellation failed: "+error;
                        return GX3DE_DEGENERATE;
                    }}
#endif
                else if(object->scientific) {
                    if(object->volume_style.enabled){
                        target->diagnostic="D3D11 scientific volume presentation is unavailable";
                        return GX3DE_UNSUPPORTED;
                    }
                    vtkNew<vtkGeometryFilter> geometry;
                    geometry->SetInputData(object->scientific->dataset);
                    geometry->Update();auto* poly=geometry->GetOutput();
                    if(poly->GetNumberOfPoints()>1000000||poly->GetNumberOfPolys()>4000000)
                        return GX3DE_RANGE;
                    extracted.vertices.reserve(size_t(poly->GetNumberOfPoints()));
                    for(vtkIdType i=0;i<poly->GetNumberOfPoints();++i) {
                        double p[3];poly->GetPoint(i,p);extracted.vertices.push_back({p[0],p[1],p[2]});
                    }
                    const vtkIdType polyStart=poly->GetNumberOfVerts()+poly->GetNumberOfLines();
                    for(vtkIdType i=0;i<poly->GetNumberOfPolys();++i) {
                        auto* cell=poly->GetCell(polyStart+i);
                        if(!cell||cell->GetNumberOfPoints()<3)continue;
                        for(vtkIdType j=1;j+1<cell->GetNumberOfPoints();++j) {
                            extracted.triangles.push_back(uint32_t(cell->GetPointId(0)));
                            extracted.triangles.push_back(uint32_t(cell->GetPointId(j)));
                            extracted.triangles.push_back(uint32_t(cell->GetPointId(j+1)));
                        }
                    }
                    mesh=&extracted;
                } else continue;
                displayed_triangles+=mesh->triangles.size()/3;
                if(displayed_triangles>target->engine->graphics.display_triangle_budget){
                    target->diagnostic="configured display triangle budget exceeded";
                    return GX3DE_RANGE;}
                auto rc=gx3de_d3d_draw(s,target,vp,object,*mesh);
                if(rc!=GX3DE_OK)return rc;
            }
        }
        s.context->CopyResource(s.staging.Get(),s.color.Get());
        D3D11_MAPPED_SUBRESOURCE mapped{};
        HRESULT hr=s.context->Map(s.staging.Get(),0,D3D11_MAP_READ,0,&mapped);
        if(FAILED(hr)){target->diagnostic=gx3de_d3d_error("D3D11 RGBA readback",hr);return GX3DE_DEGENERATE;}
        target->rgba.resize(size_t(target->width)*target->height*4);
        for(uint32_t y=0;y<target->height;++y)
            std::memcpy(target->rgba.data()+size_t(y)*target->width*4,
                static_cast<const uint8_t*>(mapped.pData)+size_t(y)*mapped.RowPitch,
                size_t(target->width)*4);
        s.context->Unmap(s.staging.Get(),0);
        if(s.swapchain) {
            ComPtr<ID3D11Texture2D> backbuffer;
            hr=s.swapchain->GetBuffer(0,IID_PPV_ARGS(backbuffer.GetAddressOf()));
            if(FAILED(hr)){target->diagnostic=gx3de_d3d_error("DXGI back buffer",hr);return GX3DE_DEGENERATE;}
            s.context->CopyResource(backbuffer.Get(),s.color.Get());
            hr=s.swapchain->Present(0,0);
            if(FAILED(hr)){target->diagnostic=gx3de_d3d_error("DXGI present",hr);return GX3DE_DEGENERATE;}
        }
        target->diagnostic="D3D11 hardware adapter: "+s.adapter;
        ++target->completed_frames;++target->geometry_rebuild_frames;
        return GX3DE_OK;
    } catch(const std::bad_alloc&) {target->diagnostic="D3D11 out of memory";
        target->rgba.clear();return GX3DE_OUT_OF_MEMORY;
    } catch(const std::exception& e) {target->diagnostic=e.what();
        target->rgba.clear();return GX3DE_DEGENERATE;}
}
#endif
