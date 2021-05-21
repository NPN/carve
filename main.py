from argparse import ArgumentParser
import queue
import sys
import threading

import av
from futhark_ffi import Futhark
import numpy as np
from tqdm import trange

try:
    import build._carve as _carve
except ModuleNotFoundError:
    print("Could not import '_carve' module. Did you run `make`?")
    sys.exit(1)

VIDEO_FORMAT = "gray8"


parser = ArgumentParser(description="Resize videos with seam carving.")
parser.add_argument("input", help="Input video file")
parser.add_argument("output", help="Output video file")
parser.add_argument("pixels", type=int, help="Number of pixels to carve")
parser.add_argument(
    "--threshold",
    default=0.3,
    type=float,
    help="Shot detection threshold (default: %(default)s)",
)
parser.add_argument(
    "--profile",
    action="store_true",
    help="Print profiling info (doesn't work with C backend)",
)
args = parser.parse_args()

if args.pixels <= 0:
    print("`pixels` must be at least 1")
    sys.exit(1)
elif not (0 <= args.threshold <= 1):
    print("`--threshold` must be between 0 and 1, inclusive")
    sys.exit(1)


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


def decode():
    with av.open(args.input, "r") as container_in:
        container_in.streams.video[0].thread_type = "AUTO"
        codec_context = container_in.streams.video[0].codec_context

        # Send input video info
        decode_queue.put(
            (
                container_in.streams.video[0].frames,
                codec_context.width,
                codec_context.height,
                codec_context.codec.name,
                codec_context.framerate,
            )
        )

        for frame in container_in.decode(video=0):
            decode_queue.put(frame)


def encode():
    with av.open(args.output, "w") as container_out:
        stream_out = container_out.add_stream(codec_name, rate=framerate)
        stream_out.width = width - args.pixels
        stream_out.height = height
        stream_out.thread_type = "AUTO"

        for _ in range(frames):
            frame = av.VideoFrame.from_ndarray(encode_queue.get(), format=VIDEO_FORMAT)
            for packet in stream_out.encode(frame):
                container_out.mux(packet)

        for packet in stream_out.encode():
            container_out.mux(packet)


decode_queue = queue.Queue()
encode_queue = queue.Queue()

decode_thread = threading.Thread(target=decode, daemon=True, name="decode")
decode_thread.start()

# Dump input video info into globals for the encode thread and other consumers
frames, width, height, codec_name, framerate = decode_queue.get()

encode_thread = threading.Thread(target=encode, daemon=True, name="encode")
encode_thread.start()


carve = Futhark(_carve, profiling=args.profile)

# We want to keep `frame` on the GPU for the duration of its carving. This
# means we need to use to_futhark(). But this requires us to know the fut_type,
# which isn't directly exposed. So, we have to search through carve.types.
for ftype in carve.types.values():
    if ftype.itemtype.cname == "uint8_t *" and ftype.rank == 2:
        u8_2d = ftype


seams = np.empty((args.pixels, height), np.int16)


def main():
    hist_dist = 0
    prev_hist = None
    # The maximum distance between two histograms is 2 * width * height (e.g.
    # one histogram has all of its pixels in bin 0, and the other has all of
    # its pixels in bin 1)
    MAX_DIST = 2 * width * height

    for i in trange(frames, unit="fr"):
        frame = carve.to_futhark(
            u8_2d, decode_queue.get().to_ndarray(format=VIDEO_FORMAT)
        )

        # If threshold is 0, then TC is always disabled, so keeping hist_dist
        # at 0 is fine.  If threshold is 1, then TC is always enabled, so we
        # still don't need to calculate the actual histogram distance.
        if not (args.threshold == 0 or args.threshold == 1):
            hist = carve.frame_histogram(frame)
            if prev_hist is not None:
                hist_dist = carve.histogram_dist(hist, prev_hist) / MAX_DIST
            prev_hist = hist

        for p in range(args.pixels):
            if i == 0 or hist_dist >= args.threshold:
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

        encode_queue.put(carve.from_futhark(frame))


main()

# Decode thread should finish first
decode_thread.join()
encode_thread.join()


if args.profile:
    # Filter, format, and sort profiling output
    import re

    REPORT_RE = re.compile(r"([^ ]+) +ran +(\d+) times; avg: +(\d+)us; total: +(\d+)us")
    raw_report = carve.report().strip().split("\n")

    peak_memory = raw_report[0].split(" ")
    print(" ".join(peak_memory[:-2]), int(peak_memory[-2]) / 1e6, "megabytes")

    total_runtime = raw_report[-1].split(" ")
    print(" ".join(total_runtime[:-1]), str(int(total_runtime[-1][:-2]) / 1e6) + "s")

    report = []
    for l in raw_report[1:-1]:
        m = REPORT_RE.fullmatch(l)
        if int(m[2]) == 0:
            continue
        report.append((m[1], int(m[2]), int(m[3]), int(m[4]) / 1000))

    report.sort(key=lambda l: l[3], reverse=True)

    for l in report:
        print(f"{l[0]:<45} ran {l[1]:>4} times, avg {l[2]:>4}us, total {l[3]:>6.2f}ms")
