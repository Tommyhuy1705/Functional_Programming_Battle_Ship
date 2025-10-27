module Game.Ship
  ( Ship(..), placeShipPositions, occupies )
where

import Game.Types

data Ship = Ship
  { shipId :: Int
  , shipType :: ShipType
  , positions :: [Pos]
  } deriving (Eq, Show)

placeShipPositions :: Pos -> Bool -> ShipType -> Maybe [Pos]
placeShipPositions (r,c) horizontal st =
  let len = shipSize st
      coords = if horizontal
               then [ (r, c+i) | i <- [0..len-1] ]
               else [ (r+i, c) | i <- [0..len-1] ]
  in if all inBounds coords then Just coords else Nothing

occupies :: Ship -> Pos -> Bool
occupies s p = p `elem` positions s
