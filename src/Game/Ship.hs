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

-- Định nghĩa kiểu dữ liệu cho tàu
data Ship = Ship
  { shipId     :: Int
  , shipType   :: ShipType
  , positions  :: [Pos]
  } deriving (Eq, Show, Generic)

instance ToJSON Ship
instance FromJSON Ship

-- Sinh ra danh sách các vị trí cho 1 con tàu
placeShipPositions :: Pos -> Bool -> ShipType -> Maybe [Pos]
placeShipPositions (r, c) horizontal st =
  let len = shipSize st
      coords = if horizontal
               then [ (r, c+i) | i <- [0..len-1] ]
               else [ (r+i, c) | i <- [0..len-1] ]
  in if all inBounds coords then Just coords else Nothing

-- ✅ Hàm này kiểm tra xem có thể đặt tàu mới hay không (không đè lên tàu khác)
placeShip :: [Ship] -> Int -> ShipType -> Pos -> Bool -> Maybe Ship
placeShip existingShips sid st pos horizontal = do
  coords <- placeShipPositions pos horizontal st
  if any (`elem` concatMap positions existingShips) coords
     then Nothing  -- 🚫 Trùng vị trí với tàu khác
     else Just (Ship sid st coords)

-- Kiểm tra một ô có nằm trong tàu không
occupies :: Ship -> Pos -> Bool
occupies s p = p `elem` positions s

-- Chuyển tên tàu dạng string thành ShipType
parseShipType :: String -> Maybe ShipType
parseShipType s = case map toLower s of
  "carrier"    -> Just Carrier
  "battleship" -> Just Battleship
  "cruiser"    -> Just Cruiser
  "submarine"  -> Just Submarine
  "destroyer"  -> Just Destroyer
  _            -> Nothing
