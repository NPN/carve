let sq_diff (frame: []u8) (a: i32) (b: i32): f32 =
  let diff = (f32.u8 (unsafe frame[a])) - (f32.u8 (unsafe frame[b]))
  in diff * diff

-- ==
-- entry: energy
-- compiled random input { [1000000]u8 1000 1000 } auto output
-- compiled random input { [4000000]u8 2000 2000 } auto output
entry energy (frame: []u8) (width: i32) (height: i32): []f32 =
  map (\i ->
    let x = i % width
    let y = i / height
    let left  = if x == 0          then i else i - 1
    let right = if x == width  - 1 then i else i + 1
    let up    = if y == 0          then i else i - width
    let down  = if y == height - 1 then i else i + width
    in (sq_diff frame left right) + (sq_diff frame up down)
  ) (iota (width * height))
