/* Existing image identity attributes own ROI persistence; native kernel validates geometry. */
static Tcl_Obj *image_roi_field(Tcl_Interp *ip,Tcl_Obj *d,const char *key){Tcl_Obj *v=NULL,*k=Tcl_NewStringObj(key,-1);int rc;Tcl_IncrRefCount(k);rc=Tcl_DictObjGet(ip,d,k,&v);Tcl_DecrRefCount(k);return rc==TCL_OK?v:NULL;}
static void image_roi_put(Tcl_Interp *ip,Tcl_Obj *d,const char *key,Tcl_Obj *v){Tcl_Obj *k=Tcl_NewStringObj(key,-1);Tcl_IncrRefCount(k);Tcl_DictObjPut(ip,d,k,v);Tcl_DecrRefCount(k);}
static int image_roi_expected(Tcl_Interp *ip,Tcl_Obj *request,Tcl_WideInt revision){
    Tcl_Obj *value=image_roi_field(ip,request,"expected_revision");Tcl_WideInt expected;
    if(!value)return TCL_OK;
    if(Tcl_GetWideIntFromObj(ip,value,&expected)!=TCL_OK)return TCL_ERROR;
    return expected==revision?TCL_OK:fail(ip,"ROI collection changed; begin a new gesture from its current revision");
}
static int image_roi_points(Tcl_Interp *ip,Tcl_Obj *record,gx2d_point points[128],int *count,int *rectangle){
    Tcl_Obj *kind=image_roi_field(ip,record,"kind"),*rows=image_roi_field(ip,record,"points"),**items;int n,i;
    if(!kind||!rows||Tcl_ListObjGetElements(ip,rows,&n,&items)!=TCL_OK)return fail(ip,"ROI geometry requires kind and points");
    *rectangle=!strcmp(Tcl_GetString(kind),"rectangle");
    if(!*rectangle&&strcmp(Tcl_GetString(kind),"polygon"))return fail(ip,"ROI kind must be rectangle or polygon");
    if(n<1||n>128||(*rectangle&&n!=2&&n!=4))return fail(ip,"Rectangle needs two opposite corners; polygon needs 1..128 draft vertices");
    for(i=0;i<n;++i)if(read_point(ip,items[i],points+i)!=TCL_OK)return TCL_ERROR;
    if(*rectangle&&n==2){gx2d_point a=points[0],b=points[1];
        points[0]=(gx2d_point){fmin(a.x,b.x),fmin(a.y,b.y)};points[1]=(gx2d_point){fmax(a.x,b.x),fmin(a.y,b.y)};
        points[2]=(gx2d_point){fmax(a.x,b.x),fmax(a.y,b.y)};points[3]=(gx2d_point){fmin(a.x,b.x),fmax(a.y,b.y)};n=4;}
    *count=n;return TCL_OK;
}
static Tcl_Obj *image_roi_geometry(gx2d_scene *scene,Tcl_Interp *ip,gx2d_id id,const char *source,Tcl_WideInt revision,
                                  const gx2d_point *points,int n,int rectangle,gx2d_status admission){
    gx2d_point device[128];Tcl_Obj *result,*canonical,*projected,*definition,*rows;int i;
    if(status(ip,gx2d_image_roi_project(scene,id,points,(size_t)n,device))!=TCL_OK)return NULL;
    result=Tcl_NewDictObj();canonical=Tcl_NewListObj(0,NULL);projected=Tcl_NewListObj(0,NULL);definition=Tcl_NewDictObj();rows=Tcl_NewListObj(0,NULL);Tcl_IncrRefCount(result);
    for(i=0;i<n;++i){Tcl_ListObjAppendElement(ip,canonical,point_obj(points[i]));Tcl_ListObjAppendElement(ip,projected,point_obj(device[i]));}
    if(rectangle){Tcl_ListObjAppendElement(ip,rows,point_obj(points[0]));Tcl_ListObjAppendElement(ip,rows,point_obj(points[2]));}
    else for(i=0;i<n;++i)Tcl_ListObjAppendElement(ip,rows,point_obj(points[i]));
    image_roi_put(ip,definition,"kind",Tcl_NewStringObj(rectangle?"rectangle":"polygon",-1));image_roi_put(ip,definition,"points",rows);
    image_roi_put(ip,definition,"source_resource_id",Tcl_NewStringObj(source,-1));
    image_roi_put(ip,result,"definition",definition);image_roi_put(ip,result,"canonical_points",canonical);image_roi_put(ip,result,"device_points",projected);
    image_roi_put(ip,result,"handles",projected);image_roi_put(ip,result,"collection_revision",Tcl_NewWideIntObj(revision));
    image_roi_put(ip,result,"source_resource_id",Tcl_NewStringObj(source,-1));image_roi_put(ip,result,"valid",Tcl_NewBooleanObj(admission==GX2D_OK));
    image_roi_put(ip,result,"admission_status",Tcl_NewStringObj(n<3?"INCOMPLETE":gx2d_status_text(admission),-1));
    return result; /* Caller releases this one owned reference. */
}
static int image_roi_interaction(gx2d_scene *scene,Tcl_Interp *ip,const char *op,gx2d_id id,
                                 const gx2d_reference_image *image,Tcl_Obj *rois,Tcl_WideInt revision,Tcl_Obj *request){
    Tcl_Obj *value,*record=NULL,*result=NULL;gx2d_point points[128],proposed[128];gx2d_status admission=GX2D_INVALID,code;
    gx2d_rect clip;double area;int inside,n=0,rectangle=0,size;
    if(Tcl_DictObjSize(ip,request,&size)!=TCL_OK||image_roi_expected(ip,request,revision)!=TCL_OK)return TCL_ERROR;
    value=image_roi_field(ip,request,"source_resource_id");
    if(value&&strcmp(Tcl_GetString(value),image->resource_id))return fail(ip,"ROI gesture source differs from the retained image");
    if(!strcmp(op,"image_roi_pick")){
        Tcl_Obj *query=image_roi_field(ip,request,"device"),*tolerance=image_roi_field(ip,request,"tolerance"),*only=image_roi_field(ip,request,"roi_id"),*key,*row,*best=NULL;
        gx2d_point device;double radius;gx2d_image_roi_hit winner={GX2D_ROI_NONE,0,INFINITY,{0,0}};Tcl_DictSearch search;int done;
        if(!query||!tolerance||read_point(ip,query,&device)!=TCL_OK||Tcl_GetDoubleFromObj(ip,tolerance,&radius)!=TCL_OK||!isfinite(radius)||radius<0)return fail(ip,"ROI picking requires finite device coordinates and a nonnegative pixel tolerance");
        if(Tcl_DictObjFirst(ip,rois,&search,&key,&row,&done)!=TCL_OK)return TCL_ERROR;
        for(;!done;Tcl_DictObjNext(&search,&key,&row,&done)){
            gx2d_image_roi_hit hit;
            if(only&&strcmp(Tcl_GetString(only),Tcl_GetString(key)))continue;
            if(image_roi_points(ip,row,points,&n,&rectangle)!=TCL_OK){Tcl_DictObjDone(&search);return TCL_ERROR;}
            code=gx2d_image_roi_pick(scene,id,points,(size_t)n,device,radius,&hit);
            if(code==GX2D_NOT_FOUND)continue;
            if(status(ip,code)!=TCL_OK){Tcl_DictObjDone(&search);return TCL_ERROR;}
            if(!best||hit.kind<winner.kind||(hit.kind==winner.kind&&hit.distance<=winner.distance)){best=key;winner=hit;}
        }
        Tcl_DictObjDone(&search);result=Tcl_NewDictObj();
        /* Semantic background/image admission uses the same authoritative
         * native picker and retained source dimensions, never Tk geometry. */
        {
            gx2d_point boundary[4]={{0,0},{image->width,0},
                {image->width,image->height},{0,image->height}};
            gx2d_image_roi_hit image_hit;
            code=gx2d_image_roi_pick(scene,id,boundary,4,device,radius,&image_hit);
            if(code!=GX2D_OK&&code!=GX2D_NOT_FOUND)return status(ip,code);
            image_roi_put(ip,result,"image_hit",Tcl_NewBooleanObj(code==GX2D_OK));
        }
        image_roi_put(ip,result,"hit",Tcl_NewBooleanObj(best!=NULL));image_roi_put(ip,result,"collection_revision",Tcl_NewWideIntObj(revision));
        image_roi_put(ip,result,"source_resource_id",Tcl_NewStringObj(image->resource_id,-1));
        if(best){image_roi_put(ip,result,"roi_id",best);image_roi_put(ip,result,"kind",Tcl_NewStringObj(winner.kind==GX2D_ROI_VERTEX?"vertex":winner.kind==GX2D_ROI_BOUNDARY?"boundary":"interior",-1));
            image_roi_put(ip,result,"index",Tcl_NewWideIntObj((Tcl_WideInt)winner.index));image_roi_put(ip,result,"distance",Tcl_NewDoubleObj(winner.distance));image_roi_put(ip,result,"device",point_obj(winner.device));}
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    value=image_roi_field(ip,request,"roi_id");
    if(value&&Tcl_DictObjGet(ip,rois,value,&record)!=TCL_OK)return TCL_ERROR;
    if(value&&!record)return fail(ip,"ROI identity does not exist");
    if(!strcmp(op,"image_roi_geometry")){
        if(!record)record=image_roi_field(ip,request,"definition");
        if(!record||image_roi_points(ip,record,points,&n,&rectangle)!=TCL_OK)return fail(ip,"ROI geometry requires an existing roi_id or a source-pixel definition");
        admission=gx2d_image_roi_validate(scene,id,points,(size_t)n,&clip,&area,&inside);
    }else if(!strcmp(op,"image_roi_propose")){
        Tcl_Obj *operation=image_roi_field(ip,request,"operation");
        if(!operation)return fail(ip,"ROI proposal requires create, translate or vertex operation");
        if(!strcmp(Tcl_GetString(operation),"create")){
            Tcl_Obj *kind=image_roi_field(ip,request,"kind"),*rows=image_roi_field(ip,request,"device_points"),**items,*definition;int i;
            if(!kind||!rows||Tcl_ListObjGetElements(ip,rows,&n,&items)!=TCL_OK||n<1||n>128)return fail(ip,"ROI creation requires kind and 1..128 device points");
            if(!strcmp(Tcl_GetString(kind),"rectangle")&&n!=2)return fail(ip,"Rectangle creation requires two opposite device corners");
            definition=Tcl_NewDictObj();Tcl_IncrRefCount(definition);Tcl_Obj *pixels=Tcl_NewListObj(0,NULL);
            image_roi_put(ip,definition,"points",pixels);
            for(i=0;i<n;++i){gx2d_point device,world,pixel;
                if(read_point(ip,items[i],&device)!=TCL_OK||status(ip,gx2d_device_to_world(scene,device,&world))!=TCL_OK||status(ip,gx2d_image_map(scene,id,world,1,&pixel))!=TCL_OK){Tcl_DecrRefCount(definition);return TCL_ERROR;}
                Tcl_ListObjAppendElement(ip,pixels,point_obj(pixel));}
            image_roi_put(ip,definition,"kind",kind);image_roi_put(ip,definition,"points",pixels);
            int parsed=image_roi_points(ip,definition,points,&n,&rectangle);Tcl_DecrRefCount(definition);if(parsed!=TCL_OK)return TCL_ERROR;
            admission=gx2d_image_roi_validate(scene,id,points,(size_t)n,&clip,&area,&inside);
        }else{
            Tcl_Obj *start=image_roi_field(ip,request,"start_device"),*end=image_roi_field(ip,request,"end_device"),*index=image_roi_field(ip,request,"index");gx2d_point a,b;Tcl_WideInt vertex=0;gx2d_image_roi_edit_mode mode;
            if(!record||image_roi_points(ip,record,points,&n,&rectangle)!=TCL_OK)return fail(ip,"ROI editing requires an existing roi_id");
            if(!start||!end||read_point(ip,start,&a)!=TCL_OK||read_point(ip,end,&b)!=TCL_OK)return fail(ip,"ROI editing requires finite start_device and end_device points");
            if(!strcmp(Tcl_GetString(operation),"translate"))mode=GX2D_ROI_TRANSLATE;
            else if(!strcmp(Tcl_GetString(operation),"vertex")){mode=GX2D_ROI_MOVE_VERTEX;if(!index||Tcl_GetWideIntFromObj(ip,index,&vertex)!=TCL_OK||vertex<0)return fail(ip,"ROI vertex editing requires a nonnegative index");}
            else return fail(ip,"ROI proposal operation must be create, translate or vertex");
            if(status(ip,gx2d_image_roi_edit(scene,id,points,(size_t)n,rectangle,mode,(size_t)vertex,a,b,proposed,&admission))!=TCL_OK)return TCL_ERROR;
            memcpy(points,proposed,(size_t)n*sizeof(*points));
        }
    }else return fail(ip,"Unknown ROI interaction operation");
    result=image_roi_geometry(scene,ip,id,image->resource_id,revision,points,n,rectangle,admission);
    if(!result)return TCL_ERROR;
    Tcl_SetObjResult(ip,result);Tcl_DecrRefCount(result);return TCL_OK;
}
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
    if(!strcmp(op,"image_roi_geometry")||!strcmp(op,"image_roi_pick")||!strcmp(op,"image_roi_propose")){
        if(argc!=5){fail(ip,"Usage: core image_roi_geometry|image_roi_pick|image_roi_propose scene image request");goto done;}
        rc=image_roi_interaction(scene,ip,op,id,&image,rois,revision,argv[4]);goto done;
    }
    if(revision==INT64_MAX){fail(ip,"ROI revision is exhausted");goto done;}
    if(argc<5||!Tcl_GetCharLength(argv[4])||Tcl_GetCharLength(argv[4])>128){fail(ip,"ROI identity must contain 1..128 characters");goto done;}
    if(!strcmp(op,"image_roi_remove")){
        if(argc!=5&&argc!=6){fail(ip,"Usage: core image_roi_remove scene image roi_id ?expected_revision?");goto done;}
        if(argc==6){Tcl_WideInt expected;if(Tcl_GetWideIntFromObj(ip,argv[5],&expected)!=TCL_OK)goto done;if(expected!=revision){fail(ip,"ROI collection changed; begin a new gesture from its current revision");goto done;}}
        Tcl_Obj *old=NULL;if(Tcl_DictObjGet(ip,rois,argv[4],&old)!=TCL_OK)goto done;if(!old){fail(ip,"ROI identity does not exist");goto done;}
        if(Tcl_DictObjRemove(ip,rois,argv[4])!=TCL_OK)goto done;
    }else if(!strcmp(op,"image_roi_set")){
        Tcl_Obj *kind,*vertices,*requested,*record,*rows;Tcl_Obj **items;gx2d_point points[128];gx2d_rect clip;double area;int n,i,inside;
        if(argc!=6){fail(ip,"Usage: core image_roi_set scene image roi_id descriptor");goto done;}
        if(Tcl_DictObjSize(ip,argv[5],&n)!=TCL_OK)goto done;
        if(image_roi_expected(ip,argv[5],revision)!=TCL_OK)goto done;
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
