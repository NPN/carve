from argparse import ArgumentParser

import av
from futhark_ffi import Futhark
import numpy as np
from tqdm import tqdm

try:
    import futhark._carve_cl as _carve
except ModuleNotFoundError as exc:
    import sys

    print("Could not import '_carve_cl' module. Did you run `make`?")
    sys.exit(1)

VIDEO_FORMAT = "gray8"


parser = ArgumentParser(description="Resize videos with seam carving.")
parser.add_argument("input", help="Input video file")
parser.add_argument("output", help="Output video file")
parser.add_argument("pixels", type=int, help="Number of pixels to carve")
args = parser.parse_args()


rng = np.random.default_rng()

# If multiple seams have the lowest energy (e.g. when carving a solid color
# background), we need to randomly choose one of them. If we always pick a
# default index instead, all the seams will be bunched together. This is fine
# for that frame, but it will destroy the following frames through the temporal
# coherence penalty.
def min_choice(x):
    min_idx = np.argmin(x)
    min_mask = x == x[min_idx]
    if np.count_nonzero(min_mask) == 1:
        return min_idx
    else:
        return rng.choice(np.nonzero(min_mask)[0])


carve = Futhark(_carve)

# We want to keep `frame` on the GPU for the duration of its carving. This
# means we need to use to_futhark(). But this requires us to know the fut_type,
# which isn't directly exposed. So, we have to search through carve.types.
for ftype in carve.types.values():
    if ftype.itemtype.cname == "uint8_t *" and ftype.rank == 2:
        u8_2d = ftype


container_in = av.open(args.input, "r")
frames = container_in.streams.video[0].frames
codec_context = container_in.streams.video[0].codec_context
width = codec_context.width
height = codec_context.height

container_out = av.open(args.output, "w")
stream_out = container_out.add_stream(
    codec_context.codec.name, rate=codec_context.framerate
)
stream_out.width = width - args.pixels
stream_out.height = height

seams = np.empty((args.pixels, height), np.int32)

for i, frame in tqdm(
    enumerate(container_in.decode(video=0)), total=frames, unit="fr", disable=None
):
    frame = carve.to_futhark(u8_2d, frame.to_ndarray(format=VIDEO_FORMAT))
    for p in range(args.pixels):
        if i == 0:
            energy = carve.energy_first(frame)
        else:
            energy = carve.energy(frame, seams[p])

        index_map = carve.index_map(energy)
        seam_energy = carve.seam_energy(energy, index_map)
        index_map, seam_energy = carve.from_futhark(index_map, seam_energy)
        min_seam_index = min_choice(seam_energy)

        # Apparently the GPU is slow at carving because it requires
        # sequentially accessing the index map (stored in global memory).
        # So, we transfer it over and do it in Python.
        for h in range(height):
            seams[p][h] = min_seam_index
            min_seam_index = index_map[h][min_seam_index]

        frame = carve.resize_frame(frame, seams[p])

    frame = av.VideoFrame.from_ndarray(carve.from_futhark(frame), format=VIDEO_FORMAT)
    for packet in stream_out.encode(frame):
        container_out.mux(packet)

container_in.close()

for packet in stream_out.encode():
    container_out.mux(packet)

container_out.close()
