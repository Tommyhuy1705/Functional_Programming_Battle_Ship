module Game.Board
  ( initBoard, boardSize, getCell, setCell, inBounds, showBoard )
where

import Game.Types

boardSize :: Int
boardSize = 10

initBoard :: Board
initBoard = replicate boardSize (replicate boardSize Empty)

inBounds :: Pos -> Bool
inBounds (r,c) = r >=0 && r < boardSize && c >=0 && c < boardSize

getCell :: Board -> Pos -> Maybe Cell
getCell b (r,c)
  | inBounds (r,c) = Just $ (b !! r) !! c
  | otherwise = Nothing

setCell :: Board -> Pos -> Cell -> Board
setCell b (r,c) val
  | not (inBounds (r,c)) = b
  | otherwise =
      let (preRows, row:postRows) = splitAt r b
          (pre, _:post) = splitAt c row
          newRow = pre ++ (val:post)
      in preRows ++ (newRow : postRows)

showBoard :: Board -> String
showBoard b = unlines $ map (unwords . map showCell) b
  where
    showCell Empty = "."
    showCell (ShipPart _) = "S"
    showCell Hit = "X"
    showCell Miss = "o"