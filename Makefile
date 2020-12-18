all: futhark/_carve_cl.o

# The actual target is something like _carve_cl.cpython-39-x86_64-linux-gnu.so,
# but this depends on the Python version. Targeting _carve_cl.o is simpler,
# though it means that changing Python versions won't cause a rebuild.
futhark/_carve_cl.o: futhark/carve_cl.c futhark/carve_cl.h
	cd futhark; build_futhark_ffi carve_cl

futhark/carve_cl.c futhark/carve_cl.h &: futhark/carve.fut
	# Change this futhark c or futhark cuda for other backends. The proper
	# way to do this would be to have separate rules, but that seems noisy. It
	# shouldn't really matter if the `_cl` suffix is wrong.
	futhark opencl --library -o futhark/carve_cl $^

clean:
	rm -f futhark/_carve_cl.* futhark/carve_cl{.c,.h}

clean-data:
	rm -rf futhark/data

clean-all: clean clean-data

.PHONY: all clean clean-data clean-all
