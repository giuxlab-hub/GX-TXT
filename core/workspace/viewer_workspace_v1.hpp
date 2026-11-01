// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "workspace_v1.hpp"
#include <functional>
#include <optional>
#include <utility>

namespace gx::workspace::v1 {
enum class DirtyDecision { save, discard, cancel };
struct ViewerHooks {
    std::function<Value()> capture;
    std::function<void(const Value&)> validate;
    std::function<void(const Value&)> restore;
    std::function<void(const Receipt&)> committed;
};

// Host-injected Session service, used on the Viewer's owning thread. Authors
// manipulate typed properties and state; persistence/transactions stay in CORE.
// With no hooks the facade's typed state is the complete editable Viewer state.
class ViewerWorkspace {
public:
    ViewerWorkspace(Store& service, Schema schema, ViewerHooks hooks = {})
        :service_(service),schema_(std::move(schema)),hooks_(std::move(hooks)) {
        service_.register_schema(schema_);
    }
    const Value& state() const {return state_;}
    const Value& properties() const {return properties_;}
    void state(Value next){validate(next);state_=std::move(next);dirty_=true;}
    void property(std::string name, Value value){
        if(!properties_.field_order.empty()&&!properties_.fields.count(name))properties_.field_order.push_back(name);
        properties_.fields[std::move(name)]=std::move(value);dirty_=true;
    }
    bool dirty() const {return dirty_;}
    // A hooked editor must signal edits just as a native property setter does.
    void changed(){dirty_=true;}
    const std::optional<Identity>& identity() const {return identity_;}
    std::vector<Summary> query(std::string prefix = {}) const {Query q;q.provider=schema_.provider;q.name_prefix=std::move(prefix);return service_.query(q);}
    Receipt status() const {require_identity();return service_.status(identity_->id);}

    bool open(const std::string& id,DirtyDecision decision=DirtyDecision::cancel){
        if(!review(decision))return false;
        auto w=service_.get(id);
        if(w.provider!=schema_.provider||w.owner!=schema_.owner||w.schema!=schema_.id||w.schema_version!=schema_.version)throw Error("SCHEMA","Viewer cannot restore this Workspace contract");
        validate(w.state);
        // Restore is the only user callback before adopting the new identity.
        // A rejected restore attempts the previous projection and retains draft.
        if(hooks_.restore){try{hooks_.restore(w.state);}catch(...){try{hooks_.restore(state_);}catch(...){}throw;}}
        state_=std::move(w.state);properties_=std::move(w.properties);identity_=w.identity;dirty_=false;return true;
    }
    Receipt save(std::string initial_name = {},bool asynchronous=false){
        auto next=capture();Receipt receipt;
        if(identity_)receipt=service_.save(*identity_,next,properties_);
        else receipt=service_.create(schema_.provider,std::move(initial_name),next,properties_);
        identity_=receipt.identity;state_=std::move(next);dirty_=false;
        if(!asynchronous){receipt=service_.flush(identity_->id);if(hooks_.committed)hooks_.committed(receipt);}
        return receipt;
    }
    Receipt save_as(std::string name,bool asynchronous=false){
        auto next=capture();auto r=service_.create(schema_.provider,std::move(name),next,properties_);
        identity_=r.identity;state_=std::move(next);dirty_=false;
        if(!asynchronous){r=service_.flush(identity_->id);if(hooks_.committed)hooks_.committed(r);}return r;
    }
    Receipt flush(){require_identity();auto r=service_.flush(identity_->id);if(hooks_.committed)hooks_.committed(r);return r;}
    Receipt rename(std::string name){require_identity();auto r=service_.rename(*identity_,std::move(name));identity_=r.identity;return service_.flush(identity_->id);}
    Receipt notes(std::string text){require_identity();auto r=service_.notes(*identity_,std::move(text));identity_=r.identity;return service_.flush(identity_->id);}
    bool close(DirtyDecision decision=DirtyDecision::cancel){
        if(!review(decision))return false;
        if(identity_)service_.flush(identity_->id);
        identity_.reset();state_=Value::object();properties_=Value::object();dirty_=false;return true;
    }
    Receipt erase(bool confirmed){require_identity();auto r=service_.erase(*identity_,confirmed);r=service_.flush(identity_->id);identity_.reset();state_=Value::object();properties_=Value::object();dirty_=false;return r;}
private:
    Store& service_;
    Schema schema_;
    ViewerHooks hooks_;
    Value state_=Value::object(),properties_=Value::object();
    std::optional<Identity> identity_;
    bool dirty_=false;
    void require_identity()const{if(!identity_)throw Error("UNSAVED","Viewer has no saved Workspace");}
    void validate(const Value& value)const{if(value.kind!=Kind::object)throw Error("TYPE","Viewer state must be an object");if(hooks_.validate)hooks_.validate(value);}
    Value capture()const{auto v=hooks_.capture?hooks_.capture():state_;validate(v);return v;}
    bool review(DirtyDecision decision){
        if(!dirty_)return true;
        if(decision==DirtyDecision::cancel)return false;
        if(decision==DirtyDecision::save){require_identity();save();}
        return true;
    }
};
}
