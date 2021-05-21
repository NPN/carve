let sq_diff a b =
  let diff = (f32.u8 a) - (f32.u8 b)
  in diff * diff

entry resize_frame [h][w] (frame: [h][w]u8) (seam: [h]i16): [h][]u8 =
  tabulate_2d h (w - 1) (\y x ->
    if i16.i64 x < seam[y] then frame[y, x] else frame[y, x + 1]
  )

-- ==
-- entry: saliency
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
entry saliency [h][w] (frame: [h][w]u8): [h][w]f32 =
  tabulate_2d h w (\y x ->
    let p = frame[y, x]
    let left  = if x == 0     then p else frame[y, x - 1]
    let right = if x == w - 1 then p else frame[y, x + 1]
    let up    = if y == 0     then p else frame[y - 1, x]
    let down  = if y == h - 1 then p else frame[y + 1, x]
    in (sq_diff left right) + (sq_diff up down)
  )

entry temporal_coherence [h][w] (frame: [h][w]u8) (seam: [h]i16): [h][w]f32 =
  let resized = resize_frame frame seam
  let both = zip frame resized

  -- How is this calculating temporal coherence (TC)? (Here, I'm only concerned
  -- about the implementation. See the paper for an explanation of TC itself.)
  -- Let's focus on one row and assume that it's 3 pixels wide. We want to
  -- calculate a particular summation of squared differences (SDs) between
  -- `frame` and `resized`. If we picture `frame` and `resized` like this:
  --
  -- frame     0   1   2
  --           | / | /
  -- resized   0   1
  --
  -- Then we'll say that `left` consists of the vertical lines `|` (SDs between
  -- elements of the same index), while `right` consists of the slanted lines
  -- `/` (SDs between elements with indexes off by one). The result we want to
  -- produce is this particular sum:
  --
  -- [ //, |/, || ]
  --
  -- We see that the first element `//` is the TC score for deleting pixel 0:
  --
  -- frame     x   1   2
  --             /   /
  -- resized   0   1
  --
  -- Similarly, the second element `|/` is the TC score for deleting pixel 1:
  --
  -- frame     0   x   2
  --           |     /
  -- resized   0   1
  --
  -- And so on for the pixel 2. Now, one way to calculate this is to do:
  --
  -- [0] ++ (scan (+) 0 [|, |])                     = [0, |, ||]
  -- (reverse (scan (+) 0 (reverse [/, /]))) ++ [0] = [//, /, 0]
  -- map2 (+) [0, |, ||] [//, /, 0]                 = [//, |/, ||]
  --
  -- But, `scan` is slow, so we want to avoid using it twice. The same goes for
  -- `reverse`. So, we do this instead:
  --
  -- map2 (-) ([0] ++ [|, |]) ([0] ++ [/, /]) = [0, | - /, | - /]
  -- scan (+) 0 [0, | - /, | - /]             = [0, | - /, || - //]
  -- f32.sum [/, /]                           = //
  -- map (+//) [0, | - /, || - //]            = [//, |/, ||]
  --
  -- In other words, we scan over the difference between `left` and `right`,
  -- then add back the sum of `right`. This requires just one `scan`, one
  -- `reduce`, and no `reverse`s.

  let left  = map (\(f, r) -> [0] ++ (map (\i -> (sq_diff f[i]   r[i])) (iota (w - 1))) :> [w]f32) both
  let right = map (\(f, r) -> [0] ++ (map (\i -> (sq_diff f[i+1] r[i])) (iota (w - 1))) :> [w]f32) both

  let scan_reduce [n] (a: [n]f32) (b: [n]f32): [n]f32 =
    let s = scan (+) 0 (map2 (-) a b)
    let b_sum = f32.sum b
    in map (+b_sum) s

  in map2 scan_reduce left right

-- ==
-- entry: spatial_coherence_horz
-- compiled random input { [1000][1000]u8 } auto output
-- compiled random input { [2000][2000]u8 } auto output
-- compiled random input { [4000][4000]u8 } auto output
entry spatial_coherence_horz [h][w] (frame: [h][w]u8): [h][w]f32 =
  tabulate_2d h w (\y x ->
    let row = frame[y]
    let diff a b = f32.abs ((f32.u8 row[x + a]) - (f32.u8 row[x + b]))
    in if      x == 0     then f32.abs ((diff   0    1)  - (diff   1  2))
       else if x == w - 1 then f32.abs ((diff (-2) (-1)) - (diff (-1) 0))
       else (diff (-1) 0) + (diff 0 1) - (diff (-1) 1)
 )

-- Energy function for the first frame. We skip temporal coherence since there's no previous frame
-- to get seams from.
entry energy_first [h][w] (frame: [h][w]u8): [h][w]f32 =
  let saliency = saliency frame
  let sc_horz = spatial_coherence_horz frame
  -- Grundmann et al. suggests "a weight ratio Sc:Tc:S of 5:1:2 for most sequences"
  in map2 (map2 (+)) (map (map (5*)) sc_horz) (map (map (2*)) saliency)

entry energy [h][w] (frame: [h][w]u8) (seam: [h]i16): [h][w]f32 =
  let saliency = saliency frame
  let tc = temporal_coherence frame seam
  let sc_horz = spatial_coherence_horz frame
  -- Grundmann et al. suggests "a weight ratio Sc:Tc:S of 5:1:2 for most sequences"
  in map3 (map3 (\x y z -> x + y + z)) (map (map (5*)) sc_horz) tc (map (map (2*)) saliency)

-- A quick and dirty way to map energy values to grayscale pixels.
entry sqrt_norm_energy [h][w] (energy: [h][w]f32): [h][w]u8 =
  let energy = map (map f32.sqrt) energy
  let max = f32.maximum (flatten energy)
  in map (map (\e -> u8.f32 (e / max * 255))) energy

-- ==
-- entry: index_map
-- compiled random input { [1000][1000]f32 } auto output
-- compiled random input { [2000][2000]f32 } auto output
-- compiled random input { [4000][4000]f32 } auto output
entry index_map [h][w] (energy: [h][w]f32): [h][w]i16 =
  tabulate_2d h w (\y x ->
    if y == h - 1 then i16.i64 x else
      -- We need <= so that seams stay vertical in uniform regions. Otherwise, every seam
      -- will slant to the left or right and some regions will never be carved.
      let min i1 i2 = if energy[y + 1, i1] <= energy[y + 1, i2] then i1 else i2
      let i = x
      let i = if x != 0     then min i (x - 1) else i
      let i = if x != w - 1 then min i (x + 1) else i
      in i16.i64 i
  )

-- We use a loop instead of reduce because "Futhark cannot generally exploit parallelism inside
-- reduction operators (except for perfect nestings of maps)."
-- Regarding the unflatten: "[it's] something I normally discourage (like concatenation, it can
-- inhibit optimisation), but writing it with direct indexing unfortunately exposed a compiler bug
-- that made the performance pretty bad."
-- Athas quoted from: https://gitter.im/futhark-lang/Lobby?at=5dfb3eb9b1701e50ca4d9005
-- Direct indexing example: https://futhark-lang.org/blog/2019-04-10-what-is-the-minimal-basis-for-futhark.html#parallel-reduction
entry seam_energy [h][w] (energy: [h][w]f32) (index: [h][w]i16): [w]f32 =
  let op (e1, i1) (e2, i2) =
    let energy_sum = map2 (\e i -> e + e2[i]) e1 i1
    let next_index = map (\i -> i2[i]) i1
    in (energy_sum, next_index)
  let as = zip energy index
  let w' = i16.i64 w
  let ne = ((map (const 0) (0..1..<w')) :> [w]f32, (0..1..<w') :> [w]i16)
  let res = loop as while length as > 1 do
              let as' = if (length as) % 2 == 1 then as ++ [ne] else as
              in map (\r -> r[0] `op` r[1])
                     (unflatten (length as' / 2) 2 as')
  in res[0].0

entry frame_histogram [h][w] (frame: [h][w]u8): [256]f32 =
  let bins = replicate 256 0
  let s = h * w
  let is = map i64.u8 (flatten frame) :> [s]i64
  let as = replicate (h * w) 1        :> [s]f32
  in reduce_by_index bins (+) 0 is as

entry histogram_dist (h1: [256]f32) (h2: [256]f32): f32 =
  -- L1 (Manhattan) distance seems to work fine
  map2 (-) h1 h2 |> map f32.abs |> f32.sum
