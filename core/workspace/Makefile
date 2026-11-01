# SPDX-License-Identifier: GPL-3.0-or-later
CXX ?= g++
CPPFLAGS += $(shell pkg-config --cflags tcl sqlite3 openssl)
CXXFLAGS ?= -O2 -g
CXXFLAGS += -std=c++17 -fPIC -Wall -Wextra -Wpedantic -pthread
LDLIBS += $(shell pkg-config --libs tcl sqlite3 openssl) -pthread
all: libgxtxt_workspace.so
libgxtxt_workspace.so: workspace_v1.cpp workspace_tcl.cpp workspace_v1.hpp workspace_json_v1.hpp workspace_capsule_v1.inc workspace_transition_v1.inc
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -shared -o $@ workspace_v1.cpp workspace_tcl.cpp $(LDLIBS)
.PHONY: all
