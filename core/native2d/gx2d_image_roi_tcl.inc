/* Existing image identity attributes own ROI persistence; native kernel validates geometry. */
static Tcl_Obj *image_roi_field(Tcl_Interp *ip,Tcl_Obj *d,const char *key){Tcl_Obj *v=NULL;if(Tcl_DictObjGet(ip,d,Tcl_NewStringObj(key,-1),&v)!=TCL_OK)return NULL;return v;}
static void image_roi_put(Tcl_Interp *ip,Tcl_Obj *d,const char *key,Tcl_Obj *v){Tcl_DictObjPut(ip,d,Tcl_NewStringObj(key,-1),v);}
static int image_roi_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){
    gx2d_id id;gx2d_reference_image image;const char *saved=NULL;Tcl_Obj *state,*rois,*revObj,*source;Tcl_WideInt revision=0;int rc=TCL_ERROR,count;
    if(argc<4||object_id(ip,argv[3],&id)!=TCL_OK)return fail(ip,"ROI operation requires an actual image identity");
    if(status(ip,gx2d_image_get(scene,id,&image))!=TCL_OK)return TCL_ERROR;
    gx2d_status code=gx2d_attribute_get(scene,id,"gx.image.rois",&saved);
    if(code!=GX2D_OK&&code!=GX2D_NOT_FOUND)return status(ip,code);
    state=saved?Tcl_NewStringObj(saved,-1):Tcl_NewDictObj();Tcl_IncrRefCount(state);
    if(Tcl_DictObjSize(ip,state,&count)!=TCL_OK)goto done;
    revObj=image_roi_field(ip,state,"revision");if(revObj&&(Tcl_GetWideIntFromObj(ip,revObj,&revision)!=TCL_OK||revision<0))goto done;
    source=image_roi_field(ip,state,"source_resource_id");if(source&&strcmp(Tcl_GetString(source),image.resource_id)){fail(ip,"ROI source identity differs from the retained image");goto done;}
    rois=image_roi_field(ip,state,"rois");rois=rois?Tcl_DuplicateObj(rois):Tcl_NewDictObj();image_roi_put(ip,state,"rois",rois);
    image_roi_put(ip,state,"source_resource_id",Tcl_NewStringObj(image.resource_id,-1));image_roi_put(ip,state,"revision",Tcl_NewWideIntObj(revision));
    if(!strcmp(op,"image_roi_get")){if(argc!=4){fail(ip,"Usage: core image_roi_get scene image");goto done;}Tcl_SetObjResult(ip,state);rc=TCL_OK;goto done;}
    if(revision==INT64_MAX){fail(ip,"ROI revision is exhausted");goto done;}
    if(argc<5||!Tcl_GetCharLength(argv[4])||Tcl_GetCharLength(argv[4])>128){fail(ip,"ROI identity must contain 1..128 characters");goto done;}
    if(!strcmp(op,"image_roi_remove")){
        if(argc!=5){fail(ip,"Usage: core image_roi_remove scene image roi_id");goto done;}
        Tcl_Obj *old=NULL;if(Tcl_DictObjGet(ip,rois,argv[4],&old)!=TCL_OK)goto done;if(!old){fail(ip,"ROI identity does not exist");goto done;}
        if(Tcl_DictObjRemove(ip,rois,argv[4])!=TCL_OK)goto done;
    }else if(!strcmp(op,"image_roi_set")){
        Tcl_Obj *kind,*vertices,*requested,*record,*rows;Tcl_Obj **items;gx2d_point points[128];gx2d_rect clip;double area;int n,i,inside;
        if(argc!=6){fail(ip,"Usage: core image_roi_set scene image roi_id descriptor");goto done;}
        if(Tcl_DictObjSize(ip,argv[5],&n)!=TCL_OK)goto done;
        kind=image_roi_field(ip,argv[5],"kind");vertices=image_roi_field(ip,argv[5],"points");requested=image_roi_field(ip,argv[5],"source_resource_id");
        if(requested&&strcmp(Tcl_GetString(requested),image.resource_id)){fail(ip,"ROI source resource must match the actual image");goto done;}
        if(!kind||!vertices||Tcl_ListObjGetElements(ip,vertices,&n,&items)!=TCL_OK){fail(ip,"ROI requires kind and source-pixel points");goto done;}
        if(!strcmp(Tcl_GetString(kind),"rectangle")){
            gx2d_point a,b;if(n!=2||read_point(ip,items[0],&a)!=TCL_OK||read_point(ip,items[1],&b)!=TCL_OK){fail(ip,"Rectangle requires two opposite source-pixel corners");goto done;}
            points[0]=(gx2d_point){fmin(a.x,b.x),fmin(a.y,b.y)};points[1]=(gx2d_point){fmax(a.x,b.x),fmin(a.y,b.y)};points[2]=(gx2d_point){fmax(a.x,b.x),fmax(a.y,b.y)};points[3]=(gx2d_point){fmin(a.x,b.x),fmax(a.y,b.y)};n=4;
        }else if(!strcmp(Tcl_GetString(kind),"polygon")){
            if(n<3||n>128){fail(ip,"Polygon requires 3..128 source-pixel vertices, without repeated closing vertex");goto done;}
            for(i=0;i<n;++i)if(read_point(ip,items[i],points+i)!=TCL_OK)goto done;
        }else{fail(ip,"ROI kind must be rectangle or polygon");goto done;}
        if(status(ip,gx2d_image_roi_validate(scene,id,points,(size_t)n,&clip,&area,&inside))!=TCL_OK)goto done;
        rows=Tcl_NewListObj(0,NULL);for(i=0;i<n;++i)Tcl_ListObjAppendElement(ip,rows,point_obj(points[i]));record=Tcl_NewDictObj();
        image_roi_put(ip,record,"kind",kind);image_roi_put(ip,record,"points",rows);image_roi_put(ip,record,"source_resource_id",Tcl_NewStringObj(image.resource_id,-1));image_roi_put(ip,record,"revision",Tcl_NewWideIntObj(revision+1));
        image_roi_put(ip,record,"area_pixels_squared",Tcl_NewDoubleObj(area));image_roi_put(ip,record,"intersects_image",Tcl_NewBooleanObj(inside));
        Tcl_Obj *bounds[4]={Tcl_NewDoubleObj(clip.x0),Tcl_NewDoubleObj(clip.y0),Tcl_NewDoubleObj(clip.x1),Tcl_NewDoubleObj(clip.y1)};image_roi_put(ip,record,"clipped_bounds",Tcl_NewListObj(4,bounds));
        if(Tcl_DictObjPut(ip,rois,argv[4],record)!=TCL_OK)goto done;
    }else{fail(ip,"Unknown image ROI operation");goto done;}
    image_roi_put(ip,state,"revision",Tcl_NewWideIntObj(revision+1));
    if(status(ip,gx2d_attribute_set(scene,id,"gx.image.rois",Tcl_GetString(state)))!=TCL_OK)goto done;
    Tcl_SetObjResult(ip,state);rc=TCL_OK;
done:Tcl_DecrRefCount(state);return rc;
}
