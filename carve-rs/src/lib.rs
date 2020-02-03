use std::convert::TryInto;
use std::ffi::CStr;
use std::ptr;

use carve_sys::*;

pub struct Context {
    cfg: *mut futhark_context_config,
    ctx: *mut futhark_context,
}

impl Context {
    pub fn new() -> Self {
        unsafe {
            let cfg = futhark_context_config_new();
            let ctx = futhark_context_new(cfg);
            Self { cfg, ctx }
        }
    }
    pub fn sync(&self) -> Result<(), String> {
        let ret = unsafe { futhark_context_sync(self.ctx) };
        if ret == 0 {
            Ok(())
        } else {
            Err(self.get_error())
        }
    }
    fn get_error(&self) -> String {
        let err = unsafe { futhark_context_get_error(self.ctx) };
        if err.is_null() {
            String::default()
        } else {
            unsafe { CStr::from_ptr(err).to_string_lossy().into_owned() }
        }
    }
}

impl Drop for Context {
    fn drop(&mut self) {
        unsafe {
            futhark_context_free(self.ctx);
            futhark_context_config_free(self.cfg);
        }
    }
}

macro_rules! array_1d {
    ($name:ident, $type:ty) => {
        paste::item! {
            pub struct $name<'c> {
                ctx: &'c Context,
                arr: *mut [<futhark_ $type _1d>],
                len: i64,
            }

            impl<'c> $name<'c> {
                pub fn new(ctx: &'c Context, data: &[$type]) -> Self {
                    let len = data.len().try_into().expect("data length out of i64 range");
                    unsafe {
                        Self {
                            ctx,
                            arr: [<futhark_new_ $type _1d>](ctx.ctx, data.as_ptr() as *mut _, len),
                            len,
                        }
                    }
                }
                fn from_raw(ctx: &'c Context, arr: *mut [<futhark_ $type _1d>]) -> Self {
                    let len = unsafe {
                        *[<futhark_shape_ $type _1d>](ctx.ctx, arr)
                    };
                    Self { ctx, arr, len }
                }
                pub fn values(&self) -> Vec<$type> {
                    let len = self.len.try_into().expect("data length out of usize range");
                    let mut values = Vec::with_capacity(len);
                    unsafe {
                        [<futhark_values_ $type _1d>](self.ctx.ctx, self.arr, values.as_mut_ptr());
                        values.set_len(len);
                    }
                    values
                }
            }

            impl<'c> Drop for $name<'c> {
                fn drop(&mut self) {
                    unsafe {
                        [<futhark_free_ $type _1d>](self.ctx.ctx, self.arr);
                    }
                }
            }
        }
    };
}

array_1d!(ArrayU8, u8);
array_1d!(ArrayF32, f32);

pub fn energy(ctx: &Context, frame: &[u8], width: u16, height: u16) -> Vec<f32> {
    let mut energy_arr_ptr = ptr::null::<futhark_f32_1d>() as *mut _;
    let frame_arr = ArrayU8::new(&ctx, frame);

    let ret = unsafe {
        futhark_entry_energy(
            ctx.ctx,
            &mut energy_arr_ptr as *mut *mut _,
            frame_arr.arr,
            width,
            height,
        )
    };
    if ret != 0 {
        panic!(ctx.get_error());
    }
    ctx.sync().expect("Failed to sync");
    let energy_arr = ArrayF32::from_raw(&ctx, energy_arr_ptr);
    energy_arr.values()
}

#[test]
fn simple_calculation() {
    let ctx = Context::new();
    let input = [32, 82, 43, 19, 14, 67, 48, 32, 54];
    let expected = [
        2669.0, 4745.0, 2097.0, 281.0, 4804.0, 2930.0, 1097.0, 360.0, 653.0,
    ];
    let actual = energy(&ctx, &input, 3, 3);

    assert_eq!(expected.len(), actual.len());
    for (e, a) in expected.iter().zip(actual.iter()) {
        assert_eq!(e, a);
    }
}

#[test]
#[should_panic]
fn wrong_width_height() {
    let ctx = Context::new();
    energy(&ctx, &[1, 2, 3], 10, 10);
}
