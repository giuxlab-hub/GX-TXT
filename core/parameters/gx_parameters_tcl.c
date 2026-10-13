/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <tcl.h>
#include "gx_parameters.h"
static int definitions(Tcl_Interp *ip,gp_context *c,Tcl_Obj *dict){
    Tcl_DictSearch search;Tcl_Obj *name,*formula;int done;
    if(Tcl_DictObjFirst(ip,dict,&search,&name,&formula,&done)!=TCL_OK)return 0;
    for(;!done;Tcl_DictObjNext(&search,&name,&formula,&done))if(!gp_define(c,Tcl_GetString(name),Tcl_GetString(formula))){Tcl_DictObjDone(&search);return 0;}
    Tcl_DictObjDone(&search);return gp_recalculate(c);
}
static int evaluate(void *data,Tcl_Interp *ip,int n,Tcl_Obj *const v[]){
    (void)data;if(n<3||n>4){Tcl_WrongNumArgs(ip,1,v,"definitions session_definitions ?expression?");return TCL_ERROR;}
    gp_context *session=gp_create(NULL),*local=gp_create(session);int code=TCL_ERROR;
    if(!session||!local){Tcl_SetObjResult(ip,Tcl_NewStringObj("Parameter allocation failed",-1));goto done;}
    if(!definitions(ip,session,v[2])){Tcl_SetObjResult(ip,Tcl_NewStringObj(gp_diagnostic(session),-1));goto done;}
    if(!definitions(ip,local,v[1])){Tcl_SetObjResult(ip,Tcl_NewStringObj(gp_diagnostic(local),-1));goto done;}
    if(n==4){double value;if(!gp_evaluate(local,Tcl_GetString(v[3]),&value)){Tcl_SetObjResult(ip,Tcl_NewStringObj(gp_diagnostic(local),-1));goto done;}Tcl_SetObjResult(ip,Tcl_NewDoubleObj(value));}
    else {Tcl_Obj *result=Tcl_NewDictObj();for(size_t i=0;i<gp_count(local);i++){
        const char *name=gp_name(local,i);double value;gp_lookup(local,name,&value);Tcl_Obj *entry=Tcl_NewDictObj();
        Tcl_DictObjPut(ip,entry,Tcl_NewStringObj("formula",-1),Tcl_NewStringObj(gp_formula(local,i),-1));
        Tcl_DictObjPut(ip,entry,Tcl_NewStringObj("value",-1),Tcl_NewDoubleObj(value));
        Tcl_DictObjPut(ip,entry,Tcl_NewStringObj("dependencies",-1),Tcl_NewStringObj(gp_dependencies(local,i),-1));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj(name,-1),entry);
    }Tcl_SetObjResult(ip,result);}code=TCL_OK;
 done:gp_destroy(local);gp_destroy(session);return code;
}
#ifdef _WIN32
__declspec(dllexport)
#endif
int Gxparameters_Init(Tcl_Interp *ip){if(!Tcl_InitStubs(ip,"8.6",0))return TCL_ERROR;Tcl_Eval(ip,"namespace eval ::GX::Parameters {}");Tcl_CreateObjCommand(ip,"::GX::Parameters::native",evaluate,NULL,NULL);return Tcl_PkgProvide(ip,"gxparameters","1.0");}
