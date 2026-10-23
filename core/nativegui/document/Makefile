# SPDX-License-Identifier: GPL-3.0-or-later
CPPFLAGS += $(shell pkg-config --cflags tcl libxml-2.0)
CFLAGS += -O2 -g -fPIC -Wall -Wextra -Werror
CXXFLAGS += -O2 -g -std=c++17 -fPIC -Wall -Wextra -Werror
LDLIBS += $(shell pkg-config --libs tcl libxml-2.0)
all: libgxtxt_document.so
libgxtxt_document.so: render.o model.o source_capture.o
	$(CXX) -shared -o $@ $^ $(LDLIBS)
model.o: source_capture.h
source_capture.o: source_capture.h
clean:
	rm -f render.o model.o source_capture.o libgxtxt_document.so
.PHONY: all clean

# Optional precompiled browser host. The legacy default document target above
# remains unchanged. All browser build output must be supplied on RAID.
HTML_QT_SDK ?=
HTML_BUILD_DIR ?=
HTML_QT_CFLAGS = $(shell pkg-config --cflags Qt6Widgets Qt6Network tcl) -I$(HTML_QT_SDK)/include/x86_64-linux-gnu/qt6 -I$(HTML_QT_SDK)/include/x86_64-linux-gnu/qt6/QtWebEngineCore -I$(HTML_QT_SDK)/include/x86_64-linux-gnu/qt6/QtWebEngineWidgets
HTML_QT_LIBS = $(shell pkg-config --libs Qt6Widgets Qt6Network tcl) -L$(HTML_QT_SDK)/lib/x86_64-linux-gnu -lQt6WebEngineWidgets -lQt6WebEngineCore
html-runtime:
	@test -n "$(HTML_QT_SDK)" -a -n "$(HTML_BUILD_DIR)" || { echo 'Supply matched HTML_QT_SDK and RAID HTML_BUILD_DIR'; exit 2; }
	@test -f "$(HTML_QT_SDK)/include/x86_64-linux-gnu/qt6/QtWebEngineWidgets/QWebEngineView"
	mkdir -p "$(HTML_BUILD_DIR)"
	$(CXX) -std=c++17 -O2 -g -Wall -Wextra -Werror $(HTML_QT_CFLAGS) html_runtime.cpp -o "$(HTML_BUILD_DIR)/gxtxt_html_runtime" $(HTML_QT_LIBS)
	"$(HTML_BUILD_DIR)/gxtxt_html_runtime" --probe-tcl > "$(HTML_BUILD_DIR)/gxtxt_html_runtime.info"
.PHONY: html-runtime
