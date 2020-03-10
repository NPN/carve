all: carve.py

carve.py: futhark/carve.fut
	futhark pyopencl --library $^ -o carve
