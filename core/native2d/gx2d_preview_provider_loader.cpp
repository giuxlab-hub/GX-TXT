/* SPDX-License-Identifier: GPL-3.0-or-later
 * Fixed Linux worker bootstrap for the existing Preview provider bridge.
 * No Tcl command, render flag or provider declaration opens native authority.
 */
#include <tcl.h>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
extern "C" int gx2d_preview_provider_v1_init(Tcl_Interp *);
extern "C" int gx2d_preview_provider_v1_enable_host_authority(Tcl_Interp *);
namespace {
bool fixed_worker(Tcl_Interp *ip) {
    if(Tcl_FindCommand(ip,"::tk",nullptr,TCL_GLOBAL_ONLY)) return false;
    const char *marker=Tcl_GetVar2(ip,"env","GXTXT_PREVIEW_WORKER",TCL_GLOBAL_ONLY);
    const char *root=Tcl_GetVar(ip,"::GX::scriptDir",TCL_GLOBAL_ONLY);
    const char *entry=Tcl_GetVar(ip,"argv0",TCL_GLOBAL_ONLY);
    if(!marker||std::string(marker)!="1"||!root||!entry||std::string(entry)!="__gxtxt_preview_worker__") return false;
    std::ifstream stream("/proc/self/cmdline",std::ios::binary);
    std::string bytes{std::istreambuf_iterator<char>(stream),std::istreambuf_iterator<char>()};
    auto first=bytes.find('\0');if(first==std::string::npos) return false;
    auto last=bytes.find('\0',first+1);if(last==std::string::npos) return false;
    std::string arg=bytes.substr(first+1,last-first-1);
    std::string expected=std::string(root)+"/core/tcl/dataset_preview_worker_v1.tcl";
    char *actual=realpath(arg.c_str(),nullptr),*wanted=realpath(expected.c_str(),nullptr);
    bool matches=actual&&wanted&&std::string(actual)==wanted;
    std::free(actual);std::free(wanted);
    return matches;
}
}
extern "C" int Gxpreviewprovider_Init(Tcl_Interp *ip) {
    if(gx2d_preview_provider_v1_init(ip)!=TCL_OK) return TCL_ERROR;
    if(fixed_worker(ip)&&gx2d_preview_provider_v1_enable_host_authority(ip)!=TCL_OK) return TCL_ERROR;
    return Tcl_PkgProvide(ip,"gxpreviewprovider","1.0");
}
