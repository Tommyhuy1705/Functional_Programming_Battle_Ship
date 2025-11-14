{-# LANGUAGE DeriveGeneric #-}
module Game.Ship
  ( Ship(..)
  , placeShipPositions
  , placeShip
  , occupies
  , parseShipType
  ) where

import Game.Types
import Game.Board (inBounds)
import GHC.Generics (Generic)
import Data.Aeson (ToJSON, FromJSON)
import Data.Char (toLower)

-- Kiểu dữ liệu tàu chiến
data Ship = Ship
  { shipId     :: Int
  , shipType   :: ShipType
  , positions  :: [Pos]
  } deriving (Eq, Show, Generic)

instance ToJSON Ship
instance FromJSON Ship

-- Tạo danh sách vị trí cho tàu (ngang/dọc)
placeShipPositions :: Pos -> Bool -> ShipType -> Maybe [Pos]
placeShipPositions (r, c) horizontal st =
  let len = shipSize st
      coords = if horizontal
               then [ (r, c+i) | i <- [0..len-1] ]
               else [ (r+i, c) | i <- [0..len-1] ]
  in if all inBounds coords then Just coords else Nothing

-- Kiểm tra có thể đặt tàu mới không (không xung đột)
placeShip :: [Ship] -> Int -> ShipType -> Pos -> Bool -> Maybe Ship
placeShip existingShips sid st pos horizontal = do
  coords <- placeShipPositions pos horizontal st
  if any (`elem` concatMap positions existingShips) coords
     then Nothing  -- Xung đột với tàu khác
     else Just (Ship sid st coords)

-- Kiểm tra ô có thuộc tàu không
occupies :: Ship -> Pos -> Bool
occupies s p = p `elem` positions s

-- Parse tên tàu (chuỗi) thành ShipType
parseShipType :: String -> Maybe ShipType
parseShipType s = case map toLower s of
  "carrier"    -> Just Carrier
  "battleship" -> Just Battleship
  "cruiser"    -> Just Cruiser
  "submarine"  -> Just Submarine
  "destroyer"  -> Just Destroyer
  _            -> Nothing
