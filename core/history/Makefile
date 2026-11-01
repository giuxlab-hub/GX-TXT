# SPDX-License-Identifier: GPL-3.0-or-later
CXX ?= g++
CPPFLAGS += $(shell pkg-config --cflags tcl openssl)
CXXFLAGS ?= -O2 -g
CXXFLAGS += -std=c++17 -fPIC -Wall -Wextra -Wpedantic -pthread
LDLIBS += $(shell pkg-config --libs tcl openssl) -pthread
all: libgxtxt_history.so
libgxtxt_history.so: history_engine.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -shared -o $@ $< $(LDLIBS)
.PHONY: all
