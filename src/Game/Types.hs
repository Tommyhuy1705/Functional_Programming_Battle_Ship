{-# LANGUAGE DeriveGeneric #-}
module Game.Types where

import GHC.Generics (Generic)
import Data.Aeson (ToJSON, FromJSON)

type Row = Int    -- 0..(boardSize-1)
type Col = Int
type Pos = (Row, Col)

data Cell = Empty | ShipPart Int -- ship id
  | Hit | Miss
  deriving (Eq, Show, Generic)

instance ToJSON Cell
instance FromJSON Cell

data ShipType = Carrier | Battleship | Cruiser | Submarine | Destroyer
  deriving (Eq, Show, Generic)

instance ToJSON ShipType
instance FromJSON ShipType

shipSize :: ShipType -> Int
shipSize Carrier    = 5
shipSize Battleship = 4
shipSize Cruiser    = 3
shipSize Submarine  = 3
shipSize Destroyer  = 2

type Board = [[Cell]]  -- rows x cols