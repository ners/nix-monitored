build: nix

BIN ?= nix-monitored
${BIN}: monitored.cc
	${CXX} ${CXXFLAGS} -std=c++17 -O2 -DPATH=\"${NIXPATH}\" -o $@ $<

BINDIR ?= ${DESTDIR}/usr/bin
install: ${BIN}
	install -D --mode=755 $< ${BINDIR}/$<
