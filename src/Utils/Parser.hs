module Utils.Parser where

import Game.Ship
import Game.Board

parseCoordinates :: String -> Maybe (Int, Int)
parseCoordinates input = undefined  -- TODO: Implement coordinate parsing

parseShipPlacement :: String -> Maybe (ShipType, (Int, Int), Orientation)
parseShipPlacement input = undefined  -- TODO: Implement ship placement parsing