-- ==
-- entry: energy
-- input  { [[158u8,  82u8, 231u8,  16u8],
--           [ 98u8,  86u8,  24u8, 153u8],
--           [ 72u8, 236u8,  76u8, 106u8],
--           [175u8, 213u8, 201u8, 118u8]] }
-- output { [[ 9376.0f32,  5345.0f32, 47205.0f32, 64994.0f32],
--           [ 7540.0f32, 29192.0f32, 28514.0f32, 24741.0f32],
--           [32825.0f32, 16145.0f32, 48229.0f32,  2125.0f32],
--           [12053.0f32,  1205.0f32, 24650.0f32,  7033.0f32]] }
-- compiled random input { [1000][1000]u8 } auto output
-- compiled random input { [2000][2000]u8 } auto output
-- compiled random input { [4000][4000]u8 } auto output
entry energy [h][w] (frame: [h][w]u8): [h][w]f32 =
  let sq_diff a b = let diff = (f32.u8 a) - (f32.u8 b) in diff * diff
  in tabulate_2d h w (\y x ->
    let left  = if x == 0     then frame[y, x] else frame[y, x - 1]
    let right = if x == w - 1 then frame[y, x] else frame[y, x + 1]
    let up    = if y == 0     then frame[y, x] else frame[y - 1, x]
    let down  = if y == h - 1 then frame[y, x] else frame[y + 1, x]
    in (sq_diff left right) + (sq_diff up down)
  )

-- A quick and dirty way to map energy values to grayscale pixels.
entry sqrt_norm_energy [h][w] (energy: [h][w]f32): [h][w]u8 =
  let energy = map (map f32.sqrt) energy
  let max = reduce (\a b -> if a > b then a else b) 0 (flatten energy)
  in map (map (\e -> u8.f32 (e / max * 255))) energy

-- ==
-- entry: index_map
-- compiled random input { [1000][1000]f32 } auto output
-- compiled random input { [2000][2000]f32 } auto output
-- compiled random input { [4000][4000]f32 } auto output
entry index_map [h][w] (energy: [h][w]f32): [h][w]i32 =
  tabulate_2d h w (\y x ->
    if y == h - 1 then 0 else
      let min i1 i2 = if energy[y + 1, i1] < energy[y + 1, i2] then i1 else i2
      let i = x
      let i = if x != 0     then min i (x - 1) else i
      let i = if x != w - 1 then min i (x + 1) else i
      in i
  )

-- We use a loop instead of reduce because "Futhark cannot generally exploit parallelism inside
-- reduction operators (except for perfect nestings of maps)."
-- Regarding the unflatten: "[it's] something I normally discourage (like concatenation, it can
-- inhibit optimisation), but writing it with direct indexing unfortunately exposed a compiler bug
-- that made the performance pretty bad."
-- Athas quoted from: https://gitter.im/futhark-lang/Lobby?at=5dfb3eb9b1701e50ca4d9005
-- Direct indexing example: https://futhark-lang.org/blog/2019-04-10-what-is-the-minimal-basis-for-futhark.html#parallel-reduction
entry max_seam_index [h][w] (energy: [h][w]f32) (index: [h][w]i32): i32 =
  let op (e1, i1) (e2, i2) =
    let energy_sum = map2 (\e i -> e + e2[i]) e1 i1
    let next_index = map (\i -> i2[i]) i1
    in (energy_sum, next_index)
  let as = zip energy index
  let ne = ((replicate w 0), (iota w))
  let res = loop as while length as > 1 do
              let as' = if (length as) % 2 == 1 then as ++ [ne] else as
              in map (\r -> r[0] `op` r[1])
                     (unflatten (length as' / 2) 2 as')
  let seam_sum = res[0].0
  in reduce (\a b -> if seam_sum[a] > seam_sum[b] then a else b) 0 (iota w)

entry resize_frame [h][w] (frame: [h][w]u8) (seam: [h]i32): [h][]u8 =
  tabulate_2d h (w - 1) (\y x ->
    if x < seam[y] then frame[y, x] else frame[y, x + 1]
  )
