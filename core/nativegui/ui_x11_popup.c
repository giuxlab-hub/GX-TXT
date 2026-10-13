/* SPDX-License-Identifier: GPL-3.0-or-later
 * Host presentation only. Reissue missing root-shadow damage for one Tk popup;
 * never render, alter pixels or change display/server configuration. */
#include <tcl.h>
#include <tk.h>
#include <X11/Xlib.h>
#include <string.h>
#include <limits.h>
/* The deployed libraries expose these stable XFixes/XDamage protocol APIs.
 * Forward declarations keep compilation independent of optional SDK packages. */
extern unsigned long XFixesCreateRegion(Display *, XRectangle *, int);
extern void XFixesDestroyRegion(Display *, unsigned long);
extern void XDamageAdd(Display *, Drawable, unsigned long);
extern Bool XDamageQueryVersion(Display *, int *, int *);
extern Bool XFixesQueryVersion(Display *, int *, int *);
static int popup_damage(ClientData unused, Tcl_Interp *ip, int objc, Tcl_Obj *const objv[]) {
    (void)unused;
    if(objc!=2){Tcl_WrongNumArgs(ip,1,objv,"mapped_popup");return TCL_ERROR;}
    Tk_Window win=Tk_NameToWindow(ip,Tcl_GetString(objv[1]),Tk_MainWindow(ip));
    if(!win)return TCL_ERROR;
    if(!Tk_IsMapped(win)||strcmp(Tk_Class(win),"ComboboxPopdown")!=0) {
        Tcl_SetObjResult(ip,Tcl_NewStringObj("Expected a mapped combobox popup",-1));return TCL_ERROR;
    }
    Display *display=Tk_Display(win);int major=1,minor=1;
    if(!XDamageQueryVersion(display,&major,&minor)||major<1||(major==1&&minor<1)) {
        Tcl_SetObjResult(ip,Tcl_NewStringObj("XDamage 1.1 is unavailable for popup presentation",-1));return TCL_ERROR;
    }
    int x,y;Tk_GetRootCoords(win,&x,&y);
    if(x<SHRT_MIN||x>SHRT_MAX||y<SHRT_MIN||y>SHRT_MAX||Tk_Width(win)>USHRT_MAX||Tk_Height(win)>USHRT_MAX) {
        Tcl_SetObjResult(ip,Tcl_NewStringObj("Popup exceeds X11 damage rectangle bounds",-1));return TCL_ERROR;
    }
    XRectangle rect={(short)x,(short)y,(unsigned short)Tk_Width(win),(unsigned short)Tk_Height(win)};
    unsigned long region=XFixesCreateRegion(display,&rect,1);
    XDamageAdd(display,RootWindowOfScreen(Tk_Screen(win)),region);
    XFixesDestroyRegion(display,region);XSync(display,False);
    Tcl_SetObjResult(ip,Tcl_NewBooleanObj(1));
    return TCL_OK;
}
int Gxtxtuix11_Init(Tcl_Interp *ip) {
    if(!Tcl_InitStubs(ip,"8.6",0)||!Tk_InitStubs(ip,"8.6",0))return TCL_ERROR;
    /* Optional compatibility transport must fail as a Tcl diagnostic before
     * issuing a region request on a server lacking either extension. */
    Display *display=Tk_Display(Tk_MainWindow(ip));
    int damage_major=1,damage_minor=1,fixes_major=2,fixes_minor=0;
    if(!XDamageQueryVersion(display,&damage_major,&damage_minor)||
       damage_major<1||(damage_major==1&&damage_minor<1)||
       !XFixesQueryVersion(display,&fixes_major,&fixes_minor)||fixes_major<2) {
        Tcl_SetObjResult(ip,Tcl_NewStringObj("XDamage 1.1 and XFixes 2.0 are required for optional popup recovery",-1));
        return TCL_ERROR;
    }
    Tcl_EvalEx(ip,"namespace eval ::GX::UiX11 {}",-1,TCL_EVAL_GLOBAL);
    Tcl_CreateObjCommand(ip,"::GX::UiX11::popupDamage",popup_damage,NULL,NULL);
    return Tcl_PkgProvide(ip,"gxtxt_ui_x11","1.0");
}
