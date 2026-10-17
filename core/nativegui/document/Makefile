# SPDX-License-Identifier: GPL-3.0-or-later
CPPFLAGS += $(shell pkg-config --cflags tcl libxml-2.0)
CFLAGS += -O2 -g -fPIC -Wall -Wextra -Werror
CXXFLAGS += -O2 -g -std=c++17 -fPIC -Wall -Wextra -Werror
LDLIBS += $(shell pkg-config --libs tcl libxml-2.0)
all: libgxtxt_document.so
libgxtxt_document.so: render.o model.o
	$(CXX) -shared -o $@ $^ $(LDLIBS)
clean:
	rm -f render.o model.o libgxtxt_document.so
.PHONY: all clean
