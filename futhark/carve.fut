let sq_diff (frame: []u8) (a: i32) (b: i32): f32 =
  let diff = (f32.u8 (unsafe frame[a])) - (f32.u8 (unsafe frame[b]))
  in diff * diff

-- ==
-- entry: energy
-- input  { [158u8,  82u8, 231u8,  16u8,
--            98u8,  86u8,  24u8, 153u8,
--            72u8, 236u8,  76u8, 106u8,
--           175u8, 213u8, 201u8, 118u8]
--          4u16 4u16 }
-- output { [9376.0f32,  5345.0f32, 47205.0f32, 64994.0f32,
--           7540.0f32, 29192.0f32, 28514.0f32, 24741.0f32,
--          32825.0f32, 16145.0f32, 48229.0f32,  2125.0f32,
--          12053.0f32,  1205.0f32, 24650.0f32,  7033.0f32] }
-- compiled random input { [1000000]u8 1000u16 1000u16 } auto output
-- compiled random input { [4000000]u8 2000u16 2000u16 } auto output
entry energy [n] (frame: [n]u8) (width: u16) (height: u16): [n]f32 =
  let width  = i32.u16 width
  let height = i32.u16 height
  in map (\i ->
    let x = i % width
    let y = i / height
    let left  = if x == 0          then i else i - 1
    let right = if x == width  - 1 then i else i + 1
    let up    = if y == 0          then i else i - width
    let down  = if y == height - 1 then i else i + width
    in (sq_diff frame left right) + (sq_diff frame up down)
  ) (iota (width * height))
