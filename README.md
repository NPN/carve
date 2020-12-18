# carve

Resizing videos with seam carving.

## Building

Install the Python dependencies from `requirements.txt`. Then, follow the [instructions to install Futhark](https://futhark.readthedocs.io/en/stable/installation.html). If you want to use the OpenCL or CUDA backends, you will need the corresponding libraries. See the preceeding link for more details.

Then, type `make`. This will compile the Futhark code into a library and use [`build_futhark_ffi`](https://github.com/pepijndevos/futhark-pycffi) to generate Python bindings. Currently, this only builds for OpenCL, but this can easily be changed—see the `Makefile` for details. (It is highly advised to use OpenCL or CUDA, as the C backend is far too slow for practical use.)

## Usage

```
python main.py [input video] [output video] [pixels to carve]
```

Any codec or container supported by FFmpeg should work. Some codecs, such as x264, may require that the video have even dimensions. In that case, the number of pixels to carve must be even.

Currently, color is not supported, so the video will be converted to grayscale.

## References

This project is based on the following research:

* Kim, I., Zhai, J., Li, Y. et al. Optimizing seam carving on multi-GPU systems for real-time content-aware image resizing. J Supercomput 71, 3500–3524 (2015). ([link to paper](https://hpc.cs.tsinghua.edu.cn/research/cluster/papers_cwg/icpads14.pdf))
* M. Grundmann, V. Kwatra, M. Han and I. Essa, "Discontinuous seam-carving for video retargeting," 2010 IEEE Computer Society Conference on Computer Vision and Pattern Recognition, San Francisco, CA, 2010, pp. 569-576. ([link to paper](https://www.cc.gatech.edu/cpl/projects/videoretargeting/cvpr2010_videoretargeting.pdf))
