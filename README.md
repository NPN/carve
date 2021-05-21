# carve

Resizing videos with GPU seam carving.

## Building

Install the Python dependencies from `requirements.txt`. Then, follow the [instructions to install Futhark](https://futhark.readthedocs.io/en/stable/installation.html). If you want to use the OpenCL or CUDA backends, you will need the corresponding libraries. See the preceeding link for more details.

Then, type `make`. This will compile the Futhark code into a library and use [`build_futhark_ffi`](https://github.com/pepijndevos/futhark-pycffi) to generate Python bindings. By default, this builds for OpenCL, but you can change this by editing the `Makefile` or passing an argument (e.g. `make BACKEND=cuda`). Note that switching backends will require running `make clean` first.

## Usage

```
python main.py [input video] [output video] [pixels to carve]
```

Any codec or container supported by FFmpeg should work. Some codecs, such as x264, may require that the video have even dimensions. In that case, the number of pixels to carve must be even.

Currently, color is not supported, so the video will be converted to grayscale.

Temporal coherence does not work well on abrupt cuts, so a simple heuristic (L1 distance on luma histograms) is used to [detect shot transitions](https://en.wikipedia.org/wiki/Shot_transition_detection). Use `--threshold` to configure the sensitivity of this heuristic. If the distance between two frames is below `--threshold`, then they will be considered a single shot, and temporal coherence will be enabled. If the distance is at or above `--threshold`, then the frames will be considered different shots, and temporal coherence will be disabled for that frame. In an extreme case, if `--threshold` is set to 0, then temporal coherence will always be disabled, and if it's set to `1`, then temporal coherence will always be enabled.

If you want to reduce the height of the video instead of the width, flip the video before carving and then flip it back afterwards. It doesn't matter how you flip it so long as the height and width are exchanged. For example:
```
ffmpeg -i video.mp4 -vf transpose video-flip.mp4
python main.py video-flip.mp4 video-flip-carve.mp4 100
ffmpeg -i video-flip-carve.mp4 -vf transpose video-carve.mp4
```
This will result in a quality loss due to reencoding. In the future, an option could be added to flip the video internally to avoid this.

## References

This project is based on the following research:

* Kim, I., Zhai, J., Li, Y. et al. Optimizing seam carving on multi-GPU systems for real-time content-aware image resizing. J Supercomput 71, 3500–3524 (2015). ([link to paper](https://hpc.cs.tsinghua.edu.cn/research/cluster/papers_cwg/icpads14.pdf))
* M. Grundmann, V. Kwatra, M. Han and I. Essa, "Discontinuous seam-carving for video retargeting," 2010 IEEE Computer Society Conference on Computer Vision and Pattern Recognition, San Francisco, CA, 2010, pp. 569-576. ([link to paper](https://www.cc.gatech.edu/cpl/projects/videoretargeting/cvpr2010_videoretargeting.pdf))
