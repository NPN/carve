use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=../carve-fut/carve.fut");

    let out_dir = env::var("OUT_DIR").unwrap();
    let out_path = PathBuf::from(&out_dir);

    Command::new("futhark")
        .args(&[
            if cfg!(feature = "opencl") {
                "opencl"
            } else {
                "c"
            },
            "--library",
            "-o",
            &format!("{}/carve", &out_dir),
            "../carve-fut/carve.fut",
        ])
        .status()
        .expect("Failed to compile Futhark code");

    cc::Build::new()
        .file(out_path.join("carve.c"))
        .shared_flag(true)
        .compile("carve");

    if cfg!(feature = "opencl") {
        println!("cargo:rustc-link-lib=OpenCL");
    }

    let bindings = bindgen::Builder::default()
        .header(format!("{}/carve.h", &out_dir))
        .generate()
        .expect("Failed to generate bindings");
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Failed to write bindings");
}
