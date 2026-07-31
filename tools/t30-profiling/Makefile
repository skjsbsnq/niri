# Build the T-30 virtual-pointer driver.
# Needs: wayland-client (pkg-config), wayland-scanner.

XML := wlr-virtual-pointer-unstable-v1.xml
GEN_H := wlr-virtual-pointer-unstable-v1-client.h
GEN_C := wlr-virtual-pointer-unstable-v1-protocol.c

all: vpointer

$(GEN_H) $(GEN_C): $(XML)
	wayland-scanner client-header $(XML) $(GEN_H)
	wayland-scanner private-code $(XML) $(GEN_C)

vpointer: vpointer.c $(GEN_H) $(GEN_C)
	$(CC) $(CFLAGS) -Wall -Wextra -O2 -o $@ vpointer.c $(GEN_C) \
		$$(pkg-config --cflags --libs wayland-client) -lm

clean:
	rm -f vpointer $(GEN_H) $(GEN_C)

.PHONY: all clean
