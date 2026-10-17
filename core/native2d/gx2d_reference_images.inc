/* SPDX-License-Identifier: GPL-3.0-or-later */
static long double image_roi_cross(gx2d_point a,gx2d_point b,gx2d_point c){return ((long double)b.x-a.x)*((long double)c.y-a.y)-((long double)b.y-a.y)*((long double)c.x-a.x);}
static int image_roi_on(gx2d_point a,gx2d_point b,gx2d_point p){return image_roi_cross(a,b,p)==0&&p.x>=fmin(a.x,b.x)&&p.x<=fmax(a.x,b.x)&&p.y>=fmin(a.y,b.y)&&p.y<=fmax(a.y,b.y);}
static int image_roi_intersects(gx2d_point a,gx2d_point b,gx2d_point c,gx2d_point d){long double x=image_roi_cross(a,b,c),y=image_roi_cross(a,b,d),u=image_roi_cross(c,d,a),v=image_roi_cross(c,d,b);return (((x<0&&y>0)||(x>0&&y<0))&&((u<0&&v>0)||(u>0&&v<0)))||image_roi_on(a,b,c)||image_roi_on(a,b,d)||image_roi_on(c,d,a)||image_roi_on(c,d,b);}
gx2d_status gx2d_path_validate(const gx2d_point *p,size_t n,int closed,double *length,double *area){
    size_t i,j,segments;long double sum=0,total=0;
    if(!p||!length||!area||n<3||n>4096||(closed!=0&&closed!=1))return GX2D_INVALID;
    if(closed&&p[0].x==p[n-1].x&&p[0].y==p[n-1].y)--n;
    if(n<3)return GX2D_INVALID;segments=closed?n:n-1;
    for(i=0;i<n;++i){if(!finite2(p[i]))return GX2D_INVALID;}
    for(i=0;i<segments;++i){gx2d_point a=p[i],b=p[(i+1)%n];double d=dist(a,b);if(d==0||!isfinite(d))return GX2D_INVALID;total+=d;
        if(i+1<segments){gx2d_point c=p[(i+2)%n];if(image_roi_cross(a,b,c)==0&&((long double)b.x-a.x)*((long double)c.x-b.x)+((long double)b.y-a.y)*((long double)c.y-b.y)<0)return GX2D_INVALID;}
        sum+=((long double)a.x-p[0].x)*((long double)b.y-p[0].y)-((long double)b.x-p[0].x)*((long double)a.y-p[0].y);
        for(j=i+2;j<segments;++j){if(closed&&i==0&&j==segments-1)continue;if(image_roi_intersects(a,b,p[j],p[(j+1)%n]))return GX2D_INVALID;}
    }
    if(!isfinite((double)total)||!isfinite((double)sum)||(closed&&sum==0))return GX2D_INVALID;
    *length=(double)total;*area=closed?(double)(sum/2):0;return GX2D_OK;
}
gx2d_status gx2d_image_roi_validate(const gx2d_scene *s,gx2d_id id,const gx2d_point *p,size_t n,gx2d_rect *clip,double *area,int *inside){
    gx2d_reference_image image;gx2d_status code;size_t i,j;long double sum=0;gx2d_rect bounds;
    if(!p||n<3||n>128||!clip||!area||!inside)return GX2D_INVALID;
    code=gx2d_image_get(s,id,&image);if(code!=GX2D_OK)return code;
    bounds=(gx2d_rect){p[0].x,p[0].y,p[0].x,p[0].y};
    for(i=0;i<n;++i){gx2d_point a=p[i],b=p[(i+1)%n],c=p[(i+2)%n];if(!finite2(a))return GX2D_INVALID;
        for(j=0;j<i;++j)if(a.x==p[j].x&&a.y==p[j].y)return GX2D_INVALID;
        if(image_roi_cross(a,b,c)==0&&((long double)b.x-a.x)*((long double)c.x-b.x)+((long double)b.y-a.y)*((long double)c.y-b.y)<0)return GX2D_INVALID;
        bounds.x0=fmin(bounds.x0,a.x);bounds.x1=fmax(bounds.x1,a.x);bounds.y0=fmin(bounds.y0,a.y);bounds.y1=fmax(bounds.y1,a.y);
        sum+=((long double)a.x-p[0].x)*((long double)b.y-p[0].y)-((long double)b.x-p[0].x)*((long double)a.y-p[0].y);
        for(j=i+1;j<n;++j){if(j==i+1||(i==0&&j==n-1))continue;if(image_roi_intersects(a,b,p[j],p[(j+1)%n]))return GX2D_INVALID;}
    }
    if(sum==0||!isfinite((double)(fabsl(sum)/2)))return GX2D_INVALID;*area=(double)(fabsl(sum)/2);if(*area==0)return GX2D_RANGE;
    *inside=0;
    gx2d_point corners[4]={{0,0},{image.width,0},{image.width,image.height},{0,image.height}};
    for(i=0;i<n;++i){gx2d_point a=p[i],b=p[(i+1)%n];if(a.x>=0&&a.x<=image.width&&a.y>=0&&a.y<=image.height)*inside=1;
        for(j=0;j<4;++j)if(image_roi_intersects(a,b,corners[j],corners[(j+1)%4]))*inside=1;
    }
    for(j=0;j<4&&!*inside;++j){int odd=0;for(i=0;i<n;++i){gx2d_point a=p[i],b=p[(i+1)%n];if((a.y>corners[j].y)!=(b.y>corners[j].y)){long double x=a.x+((long double)corners[j].y-a.y)*((long double)b.x-a.x)/((long double)b.y-a.y);if(x>corners[j].x)odd=!odd;}}if(odd)*inside=1;}
    *clip=(gx2d_rect){fmax(0,fmin(image.width,bounds.x0)),fmax(0,fmin(image.height,bounds.y0)),fmax(0,fmin(image.width,bounds.x1)),fmax(0,fmin(image.height,bounds.y1))};return GX2D_OK;
}
/* Raster dimensions/calibration live on the existing object identity. Its
 * retained rectangle matrix and style are the sole transform/visibility state. */
static int image_valid(const gx2d_reference_image *v){
    if(!v||!memchr(v->resource_id,0,sizeof(v->resource_id))||!v->resource_id[0]||!memchr(v->length_unit,0,sizeof(v->length_unit))||!v->length_unit[0])return 0;
    if(!isfinite(v->width)||!isfinite(v->height)||v->width<=0||v->height<=0||v->width>32768||v->height>32768||v->width*v->height>64000000)return 0;
    if(!isfinite(v->scale)||v->scale<=0||!isfinite(v->rotation)||!finite2(v->translation)||!isfinite(v->opacity)||v->opacity<0||v->opacity>1)return 0;
    if((v->visible!=0&&v->visible!=1)||(v->locked!=0&&v->locked!=1)||(v->calibrated!=0&&v->calibrated!=1))return 0;
    if(v->calibrated&&(!finite2(v->calibration[0])||!finite2(v->calibration[1])||dist(v->calibration[0],v->calibration[1])<=0||!isfinite(v->calibrated_distance)||v->calibrated_distance<=0))return 0;
    if(v->calibrated)for(size_t i=0;i<2;i++)if(v->calibration[i].x<0||v->calibration[i].y<0||v->calibration[i].x>v->width||v->calibration[i].y>v->height)return 0;
    return 1;
}
static gx2d_sketch_definition image_definition(const gx2d_reference_image *v,gx2d_point controls[2]){
    gx2d_sketch_definition d={0};controls[0]=(gx2d_point){0,0};controls[1]=(gx2d_point){v->width,v->height};
    d.family=GX2D_SKETCH_RECTANGLE;d.controls=controls;d.control_count=2;
    d.matrix[0]=d.matrix[3]=v->scale*cos(v->rotation);d.matrix[1]=-v->scale*sin(v->rotation);d.matrix[2]=v->scale*sin(v->rotation);d.matrix[4]=v->translation.x;d.matrix[5]=v->translation.y;return d;
}
static void image_metadata(object *o,const gx2d_reference_image *v){
    memcpy(o->image.resource_id,v->resource_id,sizeof(v->resource_id));memcpy(o->image.length_unit,v->length_unit,sizeof(v->length_unit));
    o->image.width=v->width;o->image.height=v->height;o->image.calibrated=v->calibrated;
    memcpy(o->image.calibration,v->calibration,sizeof(v->calibration));o->reference_image=1;
    o->style.opacity=v->opacity;o->style.visible=v->visible;o->style.locked=v->locked;
}
gx2d_status gx2d_image_create(gx2d_scene *s,const gx2d_reference_image *v,gx2d_id *out){
    if(!s||!out||!image_valid(v))return GX2D_INVALID;
    if(v->calibrated&&fabs(v->calibrated_distance-v->scale*dist(v->calibration[0],v->calibration[1]))>1e-10*fmax(1,v->calibrated_distance))return GX2D_INVALID;
    gx2d_point controls[2];gx2d_sketch_definition d=image_definition(v,controls);gx2d_id id;gx2d_status code=gx2d_sketch_create(s,&d,5,&id);
    if(code!=GX2D_OK)return code;
    code=gx2d_geometry_role_set(s,id,GX2D_ROLE_REFERENCE);
    if(code!=GX2D_OK){gx2d_delete_object(s,id);return code;}
    image_metadata(obj(s,id),v);*out=id;return GX2D_OK;
}
gx2d_status gx2d_image_get(const gx2d_scene *s,gx2d_id id,gx2d_reference_image *out){
    const object *o=cobj(s,id);if(!s||!out)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(!o->reference_image)return GX2D_INVALID;
    gx2d_reference_image v={0};const double *m=o->sketch->matrix;double scale=hypot(m[0],m[2]);
    if(fabs(scale-hypot(m[1],m[3]))>1e-10*fmax(1,scale)||fabs(m[0]*m[1]+m[2]*m[3])>1e-10*fmax(1,scale*scale)||m[0]*m[3]-m[1]*m[2]<=0)return GX2D_INVALID;
    memcpy(v.resource_id,o->image.resource_id,sizeof(v.resource_id));memcpy(v.length_unit,o->image.length_unit,sizeof(v.length_unit));
    v.width=o->image.width;v.height=o->image.height;v.scale=scale;v.rotation=atan2(m[2],m[0]);v.translation=(gx2d_point){m[4],m[5]};
    /* The retained similarity matrix is the sole scale authority. Report the
     * currently mapped distance; never maintain a second calibration scale. */
    v.opacity=o->style.opacity;v.visible=o->style.visible;v.locked=o->style.locked;v.calibrated=o->image.calibrated;v.calibrated_distance=o->image.calibrated?scale*dist(o->image.calibration[0],o->image.calibration[1]):0;memcpy(v.calibration,o->image.calibration,sizeof(v.calibration));
    *out=v;return GX2D_OK;
}
gx2d_status gx2d_image_update(gx2d_scene *s,gx2d_id id,const gx2d_reference_image *v){
    gx2d_reference_image old;gx2d_status code;if(!s||!image_valid(v))return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    code=gx2d_image_get(s,id,&old);if(code!=GX2D_OK)return code;
    if(strcmp(old.resource_id,v->resource_id)||old.width!=v->width||old.height!=v->height)return GX2D_INVALID;
    int transform=old.scale!=v->scale||old.rotation!=v->rotation||old.translation.x!=v->translation.x||old.translation.y!=v->translation.y;
    int calibration=old.calibrated!=v->calibrated||memcmp(old.calibration,v->calibration,sizeof(old.calibration));
    /* Calibration reference ordinals are immutable while relationships own
     * them. Reject reassignment before any transform/metadata can be committed. */
    int controls_changed=old.calibrated!=v->calibrated||memcmp(old.calibration,v->calibration,sizeof(old.calibration));
    if(controls_changed)for(size_t i=0;i<s->rule_count;i++){
        const rule *c=&s->rules[i];
        if(!c->disabled&&(c->spec.a==id||c->spec.b==id||c->axis==id))return GX2D_INVALID;
    }
    if((transform||calibration)&&!can_move(s,obj(s,id)))return GX2D_LOCKED;
    if(transform){gx2d_point controls[2];gx2d_sketch_definition d=image_definition(v,controls);code=gx2d_sketch_update(s,id,&d,5);if(code!=GX2D_OK)return code;}
    object *o=obj(s,id);image_metadata(o,v);return GX2D_OK;
}
gx2d_status gx2d_image_calibrate(gx2d_scene *s,gx2d_id id,gx2d_point a,gx2d_point b,double distance){
    gx2d_reference_image v;gx2d_status code=gx2d_image_get(s,id,&v);if(code!=GX2D_OK)return code;
    if(!finite2(a)||!finite2(b)||!isfinite(distance)||distance<=0||dist(a,b)==0)return GX2D_INVALID;
    if(a.x<0||a.y<0||a.x>v.width||a.y>v.height||b.x<0||b.y<0||b.x>v.width||b.y>v.height)return GX2D_RANGE;
    v.scale=distance/dist(a,b);v.calibration[0]=a;v.calibration[1]=b;v.calibrated_distance=distance;v.calibrated=1;
    return gx2d_image_update(s,id,&v);
}
gx2d_status gx2d_image_map(const gx2d_scene *s,gx2d_id id,gx2d_point p,int inverse,gx2d_point *out){
    const object *o=cobj(s,id);if(!s||!out||!finite2(p)||(inverse!=0&&inverse!=1))return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(!o->reference_image)return GX2D_INVALID;
    if(inverse)return interaction_inverse(o->sketch,p,out);
    gx2d_point q=sketch_world(o->sketch,p,0);if(!finite2(q))return GX2D_RANGE;*out=q;return GX2D_OK;
}
gx2d_status gx2d_preview_view(const gx2d_scene *s,int fit,double width,double height,double padding,gx2d_view *out){
    if(!s||!out||(fit!=0&&fit!=1)||!isfinite(width)||!isfinite(height)||width<16||height<16||width>4096||height>4096||!isfinite(padding)||padding<0||padding>.4)return GX2D_INVALID;
    gx2d_scene copy=*s;gx2d_view view=s->view;if(!fit)copy.aspect_mode=GX2D_ASPECT_AUTO;double sx=width/view.width,sy=height/view.height;
    view.width=width;view.height=height;view.left*=sx;view.right*=sx;view.top*=sy;view.bottom*=sy;
    gx2d_status code=gx2d_view_set(&copy,&view);if(code!=GX2D_OK)return code;
    if(fit){code=gx2d_view_fit(&copy,0);if(code==GX2D_NOT_FOUND){view.world=(gx2d_rect){0,0,1,1};code=gx2d_view_set(&copy,&view);}if(code!=GX2D_OK)return code;view=copy.view;double dx=(view.world.x1-view.world.x0)*padding,dy=(view.world.y1-view.world.y0)*padding;view.world.x0-=dx;view.world.x1+=dx;view.world.y0-=dy;view.world.y1+=dy;code=gx2d_view_set(&copy,&view);if(code!=GX2D_OK)return code;}
    *out=copy.view;return GX2D_OK;
}
