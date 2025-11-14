module Utils.Parser where

import Game.Types (ShipType)
import Game.Board (inBounds)

parseCoordinates :: String -> Maybe (Int, Int)
parseCoordinates input = Nothing  -- TODO: Cài parser tọa độ (ví dụ "A5" -> (0,4))

-- Dùng Bool cho hướng: True = ngang, False = dọc
parseShipPlacement :: String -> Maybe (ShipType, (Int, Int), Bool)
parseShipPlacement input = Nothing  -- TODO: Cài parser đặt tàu (loại, toạ độ, hướng)