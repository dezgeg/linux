.PHONY: all
all: _lkl.so

# XXX: this doesn't have the correct header dependencies
lkl_wrap.c lkl.py: ../lkl.i
	swig -I../include -python -outcurrentdir -cpperraswarn $<

_lkl.o: lkl_wrap.c
	gcc -fPIC $$(python-config --cflags) -I ../include/ -c -o $@ $< -DCONFIG_AUTO_LKL_POSIX_HOST=1

_lkl.so: _lkl.o
	gcc -shared $$(python-config --ldflags) -L.. -llkl -o $@ $<
