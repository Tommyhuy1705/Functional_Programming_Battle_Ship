module Utils.Parser where

import Game.Types (ShipType)
import Game.Board (inBounds)

parseCoordinates :: String -> Maybe (Int, Int)
parseCoordinates input = Nothing  -- TODO: Implement coordinate parsing

-- Use Bool for horizontal (True) / vertical (False) to avoid missing Orientation type
parseShipPlacement :: String -> Maybe (ShipType, (Int, Int), Bool)
parseShipPlacement input = Nothing  -- TODO: Implement ship placement parsing