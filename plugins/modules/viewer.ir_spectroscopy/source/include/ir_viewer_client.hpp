// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
namespace gx {class Host;struct Event;}
namespace ir_viewer {
struct Components {unsigned comparison_form;unsigned status;unsigned analysis_form;};
void route(gx::Host&,const gx::Event&,const Components&);
}
