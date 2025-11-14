module Game.Board
  ( Board
  , initBoard
  , boardSize
  , getCell
  , setCell
  , inBounds
  , showBoard
  )
where

import Game.Types

boardSize :: Int
boardSize = 10

initBoard :: Board
initBoard = replicate boardSize (replicate boardSize Empty)

-- Kiểm tra tọa độ nằm trong bảng hay không
inBounds :: Pos -> Bool
inBounds (r,c) = r >=0 && r < boardSize && c >=0 && c < boardSize

-- Lấy giá trị ô (Maybe Cell) — Nothing nếu vượt biên
getCell :: Board -> Pos -> Maybe Cell
getCell b (r,c)
  | inBounds (r,c) = Just $ (b !! r) !! c
  | otherwise = Nothing

-- Gán giá trị cho ô, trả về board mới (không thay nếu vượt biên)
setCell :: Board -> Pos -> Cell -> Board
setCell b (r,c) val
  | not (inBounds (r,c)) = b
  | otherwise =
    let (preRows, row:postRows) = splitAt r b
        (pre, _:post) = splitAt c row
        newRow = pre ++ (val:post)
    in preRows ++ (newRow : postRows)

-- Chuyển board thành chuỗi để in (debug)
showBoard :: Board -> String
showBoard b = unlines $ map (unwords . map showCell) b
  where
    showCell Empty = "."
    showCell (ShipPart _) = "S"
    showCell Hit = "X"
    showCell Miss = "o"