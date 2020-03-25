import argparse

import av
import numpy as np
import pyopencl as cl

import carve

VIDEO_FORMAT = "gray8"

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Resize videos with seam carving.")
    parser.add_argument("input", help="Input video file")
    parser.add_argument("output", help="Output video file")
    parser.add_argument("pixels", type=int, help="Number of pixels to carve")
    args = parser.parse_args()

    carve = carve.carve()

    container_in = av.open(args.input, "r")
    codec_context = container_in.streams.video[0].codec_context
    width = codec_context.width
    height = codec_context.height

    container_out = av.open(args.output, "w")
    stream_out = container_out.add_stream(
        codec_context.codec.name, rate=codec_context.framerate
    )
    stream_out.width = width - args.pixels
    stream_out.height = height

    seam = np.empty(height, np.int32)

    for frame in container_in.decode(video=0):
        frame = cl.array.to_device(carve.queue, frame.to_ndarray(format=VIDEO_FORMAT))
        for _ in range(args.pixels):
            energy = carve.energy(frame)
            index_map = carve.index_map(energy)
            # Copy the index map while finding the max seam to hide latency
            (h_index_map, nanny) = index_map.get_async()
            max_seam_index = carve.max_seam_index(energy, index_map)
            nanny.wait()
            # Free device's index map? Not sure if needed.
            index_map = h_index_map

            # Apparently the GPU is slow at carving because it requires
            # sequentially accessing the index map (stored in global memory).
            # So, we transfer it over and do it in Python.
            for i in range(height):
                seam[i] = max_seam_index
                max_seam_index = index_map[i][max_seam_index]

            frame = carve.resize_frame(frame, seam)

        frame = av.VideoFrame.from_ndarray(frame.get(), format=VIDEO_FORMAT)
        for packet in stream_out.encode(frame):
            container_out.mux(packet)

    container_in.close()

    for packet in stream_out.encode():
        container_out.mux(packet)

    container_out.close()
