SRC     := futhark
BUILD   := build
# Can also be `c` or `cuda`
BACKEND := opencl


all: $(BUILD)/_carve.o

# The actual target is something like _carve.cpython-39-x86_64-linux-gnu.so,
# but this depends on the Python version. Targeting _carve.o is simpler,
# though it means that changing Python versions won't cause a rebuild.
$(BUILD)/_carve.o: $(BUILD)/carve.c $(BUILD)/carve.h
	cd $(BUILD); build_futhark_ffi carve

$(BUILD)/carve.c $(BUILD)/carve.h &: $(SRC)/carve.fut
	@mkdir -p $(BUILD)
	futhark $(BACKEND) --library -o $(BUILD)/carve $^

check:
	futhark check $(SRC)/carve.fut

clean:
	rm -f $(BUILD)/_carve.* $(BUILD)/carve{.c,.h}

clean-data:
	rm -rf futhark/data

clean-all: clean clean-data

.PHONY: all clean clean-data clean-all
