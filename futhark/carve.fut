let sq_diff (a: u8) (b: u8): f32 =
  let diff = (f32.u8 a) - (f32.u8 b)
  in diff * diff

-- ==
-- entry: energy
-- input  { [[158u8,  82u8, 231u8,  16u8],
--           [ 98u8,  86u8,  24u8, 153u8],
--           [ 72u8, 236u8,  76u8, 106u8],
--           [175u8, 213u8, 201u8, 118u8]]
--          4u16 4u16 }
-- output { [[ 9376.0f32,  5345.0f32, 47205.0f32, 64994.0f32],
--           [ 7540.0f32, 29192.0f32, 28514.0f32, 24741.0f32],
--           [32825.0f32, 16145.0f32, 48229.0f32,  2125.0f32],
--           [12053.0f32,  1205.0f32, 24650.0f32,  7033.0f32]] }
-- compiled random input { [1000][1000]u8 1000u16 1000u16 } auto output
-- compiled random input { [2000][2000]u8 2000u16 2000u16 } auto output
entry energy [h][w] (frame: [h][w]u8): [h][w]f32 =
  tabulate_2d h w (\y x ->
    let left  = if x == 0     then frame[y, x] else unsafe frame[y, x - 1]
    let right = if x == w - 1 then frame[y, x] else unsafe frame[y, x + 1]
    let up    = if y == 0     then frame[y, x] else unsafe frame[y - 1, x]
    let down  = if y == h - 1 then frame[y, x] else unsafe frame[y + 1, x]
    in (sq_diff left right) + (sq_diff up down)
  )

-- A quick and dirty way to map energy values to grayscale pixels.
entry sqrt_norm_energy [h][w] (energy: [h][w]f32): [h][w]u8 =
  let energy = map (map f32.sqrt) energy
  let max = reduce (\a b -> if a > b then a else b) 0 (flatten energy)
  in map (map (\e -> u8.f32 (e / max * 255))) energy
