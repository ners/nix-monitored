BIN ?= nix-monitored
BINDIR ?= ${DESTDIR}/usr/bin
CXXFLAGS ?= -O2 -DNDEBUG

build: ${BIN}

${BIN}: monitored.cc
	${CXX} \
		${CXXFLAGS} \
		-std=c++20 \
		-DNOTIFY_ICON=\"${NOTIFY_ICON}\" \
		-DPATH=\"${NIXPATH}\" \
		-o $@ \
		$<

install: ${BIN}
	install -D --mode=755 $< ${BINDIR}/$<

.PHONY: build
