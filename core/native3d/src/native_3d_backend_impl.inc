// SPDX-License-Identifier: GPL-3.0-or-later
// Public, backend-neutral target selection and device diagnostics.
// Included after target/renderer definitions in native_3d_engine_api_v1.cpp.
static std::string backend_capability_line(const std::string& report,const char* label) {
    std::string lowered=report;
    for(char& c:lowered)if(c>='A'&&c<='Z')c=char(c-'A'+'a');
    const std::string key(label);
    auto start=lowered.find(key);
    if(start==std::string::npos)return {};
    start+=key.size();
    while(start<report.size()&&(report[start]==' '||report[start]==':'||report[start]=='\t'))++start;
    auto end=report.find_first_of("\r\n",start);
    return report.substr(start,end==std::string::npos?std::string::npos:end-start);
}
static void backend_copy(char* target,size_t capacity,const std::string& value) {
    const auto count=std::min(value.size(),capacity-1);
    std::memcpy(target,value.data(),count);target[count]='\0';
}
static bool backend_software_gl(const std::string& renderer) {
    std::string lowered=renderer;
    for(char& c:lowered)if(c>='A'&&c<='Z')c=char(c-'A'+'a');
    return lowered.find("llvmpipe")!=std::string::npos||
        lowered.find("softpipe")!=std::string::npos||
        lowered.find("swrast")!=std::string::npos||
        lowered.find("software rasterizer")!=std::string::npos||
        lowered.find("swiftshader")!=std::string::npos;
}
gx3de_result gx3de_target_renderer_backend_set(gx3de_target* target,uint32_t backend) {
    if(!target||backend>GX3DE_RENDER_BACKEND_D3D11)return GX3DE_INVALID_ARGUMENT;
    if(target->window||!target->rendered.empty()||!target->rgba.empty()) {
        target->diagnostic="renderer backend must be selected before first render";
        return GX3DE_UNSUPPORTED;
    }
    if(backend==GX3DE_RENDER_BACKEND_D3D11) {
        if((target->engine->graphics_configured||target->quality_explicit)&&
           (target->quality.msaa_samples!=0||
            target->quality.transparency_mode==GX3DE_TRANSPARENCY_DEPTH_PEEL||
            target->engine->graphics.execution==GX3DE_GRAPHICS_SOFTWARE)){
            target->diagnostic="D3D11 does not support the requested MSAA, depth peeling or software execution policy";
            return GX3DE_UNSUPPORTED;}
        const auto probe=gx3de_backend::probe_d3d11();
        if(!probe.available){target->diagnostic=probe.diagnostic;return GX3DE_UNSUPPORTED;}
    }
    target->backend_preference=backend;
    target->diagnostic.clear();
    return GX3DE_OK;
}
gx3de_result gx3de_target_renderer_info(gx3de_target* target,
                                          gx3de_renderer_device_info* out) {
    if(!target||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    gx3de_renderer_device_info result{};
    result.struct_size=sizeof(result);
    result.backend=target->backend_preference==GX3DE_RENDER_BACKEND_D3D11?
        GX3DE_RENDER_BACKEND_D3D11:GX3DE_RENDER_BACKEND_OPENGL;
    if(result.backend==GX3DE_RENDER_BACKEND_D3D11){
        const std::string prefix="D3D11 hardware adapter: ";
        if(!target->rgba.empty()){
            result.execution=GX3DE_RENDER_EXECUTION_HARDWARE;
            if(target->diagnostic.compare(0,prefix.size(),prefix)==0)
                backend_copy(result.adapter,sizeof result.adapter,target->diagnostic.substr(prefix.size()));
        }else backend_copy(result.last_error,sizeof result.last_error,target->diagnostic);
        *out=result;return GX3DE_OK;
    }
    const auto renderer=backend_capability_line(target->diagnostic,"opengl renderer string");
    const auto vendor=backend_capability_line(target->diagnostic,"opengl vendor string");
    const auto version=backend_capability_line(target->diagnostic,"opengl version string");
    backend_copy(result.adapter,sizeof result.adapter,renderer.empty()?vendor:renderer);
    backend_copy(result.driver,sizeof result.driver,version);
    if(!target->rgba.empty()) {
        const char* forced=std::getenv("LIBGL_ALWAYS_SOFTWARE");
        const bool software=backend_software_gl(renderer)||(forced&&forced[0]=='1');
        result.execution=software?GX3DE_RENDER_EXECUTION_SOFTWARE:
            (renderer.empty()?GX3DE_RENDER_EXECUTION_UNKNOWN:GX3DE_RENDER_EXECUTION_HARDWARE);
        if(software)backend_copy(result.fallback_reason,sizeof result.fallback_reason,
                                 "Mesa/software OpenGL renderer active");
    } else if(!target->diagnostic.empty()) {
        backend_copy(result.last_error,sizeof result.last_error,target->diagnostic);
        if(target->diagnostic.find("context lost")!=std::string::npos||
           target->diagnostic.find("CONTEXT_LOST")!=std::string::npos)result.context_lost=1;
    }
    *out=result;
    return GX3DE_OK;
}
