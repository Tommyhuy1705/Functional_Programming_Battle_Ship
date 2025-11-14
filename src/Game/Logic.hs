module Game.Logic
  ( ShotResult(..)
  , placeShipOnBoard
  , fireAt
  , allSunk
  )
where

import Game.Types
import Game.Board
import Game.Ship
import Data.List (find)


data ShotResult = ShotMiss | ShotHit | ShotSunk Int -- ship id
  deriving (Eq, Show)

-- Đặt tàu lên board nếu không xung đột
placeShipOnBoard :: Board -> Ship -> Maybe Board
placeShipOnBoard b ship =
  if any conflict (positions ship)
    then Nothing
    else Just $ foldl (\bd pos -> setCell bd pos (ShipPart (shipId ship))) b (positions ship)
  where
    conflict p = case getCell b p of
                   Just Empty -> False
                   Nothing    -> True   -- Vượt biên
                   Just _     -> True   -- Đè tàu hoặc ô đã đánh dấu


-- fireAt: trả về board đã cập nhật và kết quả phát bắn
fireAt :: Board -> [Ship] -> Pos -> (Board, ShotResult)
fireAt b ships pos =
  case getCell b pos of
    Nothing -> (b, ShotMiss) -- ngoài biên
    Just Empty -> (setCell b pos Miss, ShotMiss)
    Just Miss  -> (b, ShotMiss)
    Just Hit   -> (b, ShotHit)
    Just (ShipPart sid) ->
      let b' = setCell b pos Hit
          hitShip = find (\s -> shipId s == sid) ships
      in case hitShip of
           Nothing -> (b', ShotHit)
           Just ship ->
             if all (\p -> getCell b' p == Just Hit) (positions ship)
             then (b', ShotSunk sid)
             else (b', ShotHit)

-- allSunk: kiểm tra tất cả tàu đã bị chìm chưa
allSunk :: Board -> [Ship] -> Bool
allSunk bd ships = all (shipSunk bd) ships
  where
    shipSunk board s = all (\p -> getCell board p == Just Hit) (positions s)