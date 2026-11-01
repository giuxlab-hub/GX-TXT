// Custom X caption presentation only. One existing Native2D shaped metrics and
// painter owner is used; source labels, pair order and numerical ticks stay exact.
struct CaptionMeasure {double width=0,height=0;};
struct CaptionMeasurer {
 Model &model;std::map<std::string,CaptionMeasure> cache;
 CaptionMeasure operator()(const std::string &line) {
  auto found=cache.find(line);if(found!=cache.end())return found->second;
  Tcl_Obj *argv[]={s("::gx::native2d::text_metrics"),s("sans"),num(model.font),s(line)};
  for(auto value:argv)Tcl_IncrRefCount(value);
  int status=Tcl_EvalObjv(model.ip,4,argv,TCL_EVAL_GLOBAL);
  for(auto value:argv)Tcl_DecrRefCount(value);
  if(status!=TCL_OK)throw std::runtime_error(Tcl_GetStringResult(model.ip));
  auto result=Tcl_GetObjResult(model.ip);
  CaptionMeasure measured{number(model.ip,result,"width",NAN),number(model.ip,result,"height",NAN)};
  if(!std::isfinite(measured.width)||!std::isfinite(measured.height)||measured.width<0||measured.height<1)
   throw std::runtime_error("Custom X caption metrics are unavailable");
  cache.emplace(line,measured);return measured;
 }
};
struct CustomCaption {double value=0,device=0,width=0,height=0,offset=0;size_t row=0;std::string source;std::vector<std::string> lines;};
struct CaptionLayout {bool shaped=false;double height=0;std::vector<CustomCaption> captions;};
// Break only after ASCII space followed by an ASCII printable base. This never
// cuts Unicode combining/ZWJ/grapheme runs; indivisible runs are measured whole.
// Spaces remain in their original line, so concatenating lines is byte-exact.
std::vector<std::string> captionRuns(const std::string &source) {
 std::vector<std::string> result;size_t start=0;
 for(size_t i=0;i+1<source.size();++i)if(source[i]==' '&&static_cast<unsigned char>(source[i+1])>=33&&static_cast<unsigned char>(source[i+1])<=126){result.push_back(source.substr(start,i+1-start));start=i+1;}
 if(start<source.size())result.push_back(source.substr(start));
 return result;
}
CaptionLayout captionLayout(Model &m,Panel &panel) {
 CaptionLayout layout;
 if(text(m.ip,panel.x.spec.p,"tick_positions").empty())return layout;
 Ref planned(ticks(m,panel.x,panel.right-panel.left));
 for(auto tick:list(m.ip,planned.p)) {
  CustomCaption caption;caption.value=number(m.ip,tick,"value",NAN);caption.source=text(m.ip,tick,"label");
  caption.device=project(m,panel,panel.y,caption.value,panel.y.lo).x;layout.captions.push_back(std::move(caption));
 }
 if(layout.captions.empty())return layout;
 std::vector<size_t> order;for(size_t i=0;i<layout.captions.size();++i)order.push_back(i);
 std::sort(order.begin(),order.end(),[&](size_t a,size_t b){return layout.captions[a].device<layout.captions[b].device;});
 auto surface=cairo_image_surface_create(CAIRO_FORMAT_A8,1,1);auto cr=cairo_create(surface);
 cairo_select_font_face(cr,"sans",CAIRO_FONT_SLANT_NORMAL,CAIRO_FONT_WEIGHT_NORMAL);cairo_set_font_size(cr,m.font);
 std::vector<double> preferred(order.size());
 for(size_t at=0;at<order.size();++at) {
  auto &caption=layout.captions[order[at]];double nearest=double(m.width)-16;
  if(at)nearest=std::min(nearest,caption.device-layout.captions[order[at-1]].device-8);
  if(at+1<order.size())nearest=std::min(nearest,layout.captions[order[at+1]].device-caption.device-8);
  double edge=2*std::min(caption.device-8,double(m.width)-8-caption.device);
  preferred[at]=std::max(1.,std::min(nearest,edge));
  cairo_text_extents_t measured;cairo_text_extents(cr,caption.source.c_str(),&measured);
  if(std::any_of(caption.source.begin(),caption.source.end(),[](unsigned char c){return c>=128;})||std::max(measured.width,measured.x_advance)>preferred[at])layout.shaped=true;
 }
 cairo_destroy(cr);cairo_surface_destroy(surface);
 // Short ASCII custom captions retain the exact legacy/default painter path.
 if(!layout.shaped)return layout;
 CaptionMeasurer measure{m,{}};
 struct Row {double height=0;std::vector<std::pair<double,double>> intervals;};
 std::vector<Row> rows;
 for(size_t at=0;at<order.size();++at) {
  auto &caption=layout.captions[order[at]];double maximum=2*std::min(caption.device-8,double(m.width)-8-caption.device);
  if(maximum<1)throw std::runtime_error("Viewport is too small for exact custom X captions; enlarge the plot or reduce font size");
  std::string line;
  for(const auto &run:captionRuns(caption.source)) {
   if(!line.empty()&&measure(line+run).width>preferred[at]){caption.lines.push_back(line);line.clear();}
   line+=run;
  }
  if(!line.empty())caption.lines.push_back(line);
  std::string exact;for(auto &part:caption.lines){exact+=part;auto size=measure(part);caption.width=std::max(caption.width,size.width);caption.height+=size.height;}
  if(exact!=caption.source)throw std::runtime_error("Custom X caption presentation lost exact source text");
  if(caption.width>maximum)throw std::runtime_error("An indivisible custom X caption exceeds the viewport; enlarge the plot or reduce font size");
  caption.height+=2*std::max<size_t>(0,caption.lines.size()-1);
  const double left=caption.device-caption.width/2-4,right=caption.device+caption.width/2+4;
  size_t row=0;
  for(;row<rows.size();++row){bool collision=false;for(auto interval:rows[row].intervals)if(left<interval.second&&right>interval.first){collision=true;break;}if(!collision)break;}
  if(row==rows.size())rows.push_back({});
  rows[row].height=std::max(rows[row].height,caption.height);rows[row].intervals.push_back({left,right});caption.row=row;
  double total=8;for(const auto &entry:rows)total+=entry.height+4;
  if(total>m.height*.6)throw std::runtime_error("Custom X captions exceed bounded viewport capacity; enlarge the plot or reduce font size");
 }
 double top=8;std::vector<double> offsets;for(auto row:rows){offsets.push_back(top);top+=row.height+4;}
 for(auto &caption:layout.captions)caption.offset=offsets[caption.row];
 layout.height=top;return layout;
}
void captionDraw(Model &m,Tcl_Obj *out,Tcl_Obj *receipt,Panel &panel,const CaptionLayout &layout) {
 auto records=Tcl_NewListObj(0,nullptr);CaptionMeasurer measure{m,{}};
 // Muted guides retain the exact numerical tick X for staggered caption rows.
 // Exclude every shaped text rectangle; a guide never paints across a label.
 std::vector<std::array<double,4>> textBoxes;
 for(const auto &caption:layout.captions){double y=panel.bottom+caption.offset;for(const auto &line:caption.lines){auto size=measure(line);textBoxes.push_back({caption.device-size.width/2,y,caption.device+size.width/2,y+size.height});y+=size.height+2;}}
 for(const auto &caption:layout.captions){
  double start=panel.bottom+1,end=panel.bottom+caption.offset-3;
  std::vector<std::pair<double,double>> blocked;
  for(auto box:textBoxes)if(caption.device>=box[0]-3&&caption.device<=box[2]+3&&box[1]<end&&box[3]>start)blocked.push_back({box[1]-3,box[3]+3});
  std::sort(blocked.begin(),blocked.end());
  auto segment=[&](double top,double bottom){if(bottom<=top)return;auto line=primitive(out,"line",{caption.device,top,caption.device,bottom},"#88939c","",.7);put(line,"dash",values({2,3}));put(line,"presentation_role",s("custom_x_caption_guide"));put(line,"tick_value",num(caption.value));};
  for(auto interval:blocked){segment(start,std::min(end,interval.first));start=std::max(start,interval.second);}
  segment(start,end);
 }

 for(const auto &caption:layout.captions) {
  double y=panel.bottom+caption.offset;auto lineRecords=Tcl_NewListObj(0,nullptr);
  for(const auto &line:caption.lines) {
   auto size=measure(line);auto item=label(out,caption.device-size.width/2,y,line,0,m.font);
   put(item,"anchor",s("nw"));put(item,"text_engine",s("PangoCairo"));put(item,"text_engine_version",Tcl_NewIntObj(1));put(item,"font_family",s("sans"));put(item,"text_layout_size",values({size.width,size.height}));
   auto record=Tcl_NewDictObj();put(record,"text",s(line));put(record,"bounds",values({caption.device-size.width/2,y,caption.device+size.width/2,y+size.height}));Tcl_ListObjAppendElement(nullptr,lineRecords,record);y+=size.height+2;
  }
  auto record=Tcl_NewDictObj();put(record,"value",num(caption.value));put(record,"caption",s(caption.source));put(record,"device",num(caption.device));put(record,"row",Tcl_NewWideIntObj(caption.row));put(record,"lines",lineRecords);Tcl_ListObjAppendElement(nullptr,records,record);
 }
 auto record=Tcl_NewDictObj();put(record,"panel_id",s(panel.id));put(record,"engine",s("PangoCairo"));put(record,"captions",records);put(record,"height",num(layout.height));put(receipt,"custom_x_caption_layout",record);
}
