all: futhark/_carve.o

# The actual target is something like _carve.cpython-38-x86_64-linux-gnu.so,
# but this depends on the Python version. Targeting _carve.o is simpler, though
# it means that changing Python versions won't cause a rebuild.
futhark/_carve.o: futhark/carve.c futhark/carve.h
	cd futhark; build_futhark_ffi carve

futhark/carve.c futhark/carve.h &: futhark/carve.fut
	futhark opencl --library $^
