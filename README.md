# carve

Resizing videos with seam carving.

## Source Code Structure

* `carve-fut`: [Futhark](https://futhark-lang.org/) code that does the actual work
* `carve-sys`: Generated Rust bindings to `carve-fut`
* `carve-rs`: A (best-effort) safe wrapper to `carve-sys`
