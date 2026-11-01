// SPDX-License-Identifier: GPL-3.0-or-later
// Durable coordination intents, not a History journal or execution engine.
namespace {
Value transition_read(sqlite3* db,const std::string& token,const std::string& sha){
    Statement q(db,"SELECT path,parent,key,kind,text_value,integer_value,real_value,ordinal FROM transition_nodes WHERE token=? ORDER BY path");q.bind(1,token);Nodes nodes;std::size_t bytes=0;
    while(q.row()){auto key=q.text(0);Node node{q.text(1),q.text(2),q.text(4),static_cast<Kind>(q.integer(3)),q.integer(7),q.integer(5),sqlite3_column_double(q.s,6)};bytes+=key.size()+node.text.size()+node.key.size()+64;if(nodes.size()>=MaxNodes*4||bytes>MaxBytes*8)fail("CORRUPT","Transition intent exceeds bounds");nodes.emplace(key,std::move(node));}
    if(!nodes.count("intent"))fail("CORRUPT","Transition intent root missing");
    auto children=child_index(nodes);std::set<std::string> visited;auto value=expand(nodes,children,"intent",visited);if(visited.size()!=nodes.size()||archive_hash(value)!=sha)fail("CORRUPT","Transition intent digest differs");return value;
}
}
std::string Store::transition_prepare(const Identity& expected,Value intent){
    if(intent.kind!=Kind::object)fail("TYPE","Transition intent must be a typed object");
    std::size_t size=0;for(const auto& [key,value]:intent.fields)size+=value_size(value);if(size>MaxBytes*4)fail("LIMIT","Transition intent exceeds 64 MiB");
    flush(expected.id);std::unique_lock<std::mutex> guard(p->mutex);p->expected(expected);auto key="transition_"+random_hex();p->recovery_pending=true;
    try{auto future=p->read_submit<std::string>([expected,key,intent=std::move(intent)](sqlite3* db){sql(db,"BEGIN IMMEDIATE");try{Statement put(db,"INSERT INTO transitions VALUES(?,?,?,?,?,?)");put.bind(1,key);put.bind(2,expected.id);put.bind(3,expected.generation);put.bind(4,static_cast<std::int64_t>(expected.revision));put.bind(5,"prepared");put.bind(6,archive_hash(intent));put.row();Nodes nodes;flatten(nodes,intent,"intent");Statement node(db,"INSERT INTO transition_nodes VALUES(?,?,?,?,?,?,?,?,?)");for(const auto& [path,value]:nodes){node.reset();node.bind(1,key);node.bind(2,path);node.bind(3,value.parent);node.bind(4,value.key);node.bind(5,static_cast<std::int64_t>(value.kind));node.bind(6,value.text);node.bind(7,value.integer);node.bind(8,value.real);node.bind(9,value.ordinal);node.row();}sql(db,"COMMIT");}catch(...){sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr);throw;}return key;});guard.unlock();return *future.get();}catch(...){if(!guard.owns_lock())guard.lock();p->recovery_pending=false;throw;}
}
Value Store::transition_list(){
    std::unique_lock<std::mutex> guard(p->mutex);auto future=p->read_submit<Value>([](sqlite3* db){Value result=Value::array();Statement q(db,"SELECT token,workspace,generation,revision,phase,sha256 FROM transitions ORDER BY token");while(q.row()){if(!result.elements.empty())fail("CORRUPT","Multiple unresolved Workspace transitions");result.elements.push_back(Value::object({{"token",Value::string(q.text(0))},{"workspace",Value::string(q.text(1))},{"generation",Value::string(q.text(2))},{"revision",Value::number(q.integer(3))},{"phase",Value::string(q.text(4))},{"content",transition_read(db,q.text(0),q.text(5))}}));}return result;});guard.unlock();return *future.get();
}
Receipt Store::transition_commit(const std::string& token,const Identity& expected,Value state,Value properties){
    auto list=transition_list();if(list.elements.size()!=1||list.elements[0].fields.at("token").text!=token||list.elements[0].fields.at("phase").text!="prepared"||list.elements[0].fields.at("workspace").text!=expected.id||list.elements[0].fields.at("generation").text!=expected.generation||static_cast<std::uint64_t>(list.elements[0].fields.at("revision").integer)!=expected.revision)fail("CONFLICT","Prepared transition identity differs");
    p->ensure_loaded(expected.id);std::lock_guard<std::mutex> guard(p->mutex);p->recovery_pending=false;try{auto w=p->expected(expected).value;w.state=std::move(state);w.properties=std::move(properties);p->validate(w);++w.identity.revision;w.updated_at=now();auto receipt=p->submit(std::move(w));p->queue.back().transition_token=token;p->recovery_pending=true;return receipt;}catch(...){p->recovery_pending=true;throw;}
}
void Store::transition_finish(const std::string& token){
    std::unique_lock<std::mutex> guard(p->mutex);auto future=p->read_submit<bool>([token](sqlite3* db){Statement remove(db,"DELETE FROM transitions WHERE token=?");remove.bind(1,token);remove.row();if(sqlite3_changes(db)!=1)fail("MISSING","Workspace transition token is unavailable");return true;});guard.unlock();future.get();guard.lock();p->recovery_pending=false;
}
