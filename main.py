import argparse

import av

import carve

VIDEO_FORMAT = "gray8"

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Resize videos with seam carving.")
    parser.add_argument("input", help="Input video file")
    parser.add_argument("output", help="Output video file")
    args = parser.parse_args()

    carve = carve.carve()

    container_in = av.open(args.input, "r")
    codec_context = container_in.streams.video[0].codec_context

    container_out = av.open(args.output, "w")
    stream_out = container_out.add_stream(
        codec_context.codec.name, rate=codec_context.framerate
    )
    stream_out.width = codec_context.width
    stream_out.height = codec_context.height

    for frame in container_in.decode(video=0):
        nd_frame = frame.to_ndarray(format=VIDEO_FORMAT)
        norm_energy = carve.sqrt_norm_energy(carve.energy(nd_frame)).get()
        frame = av.VideoFrame.from_ndarray(norm_energy, format=VIDEO_FORMAT)
        for packet in stream_out.encode(frame):
            container_out.mux(packet)

    container_in.close()

    for packet in stream_out.encode():
        container_out.mux(packet)

    container_out.close()
