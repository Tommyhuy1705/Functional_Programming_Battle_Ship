{-# LANGUAGE DeriveGeneric #-}
module Network.Message
  ( GamePhase(..)
  , ClientMsg(..)
  , ServerMsg(..)
  , encodeClientMsg
  , decodeClientMsg
  )
where

import GHC.Generics (Generic)
import Data.Aeson (ToJSON, FromJSON, encode, decode)
import qualified Data.ByteString.Lazy.Char8 as BL
import Game.Types (Pos, Board)

data GamePhase = WaitingPlayers | PlacingShips | Playing | GameOver
  deriving (Show, Generic, Eq)

instance ToJSON GamePhase
instance FromJSON GamePhase

data ClientMsg
  = CMReady                    -- ready to start
  | CMPlaceShip { psShipId :: Int, psType :: String, psPos :: Pos, psHoriz :: Bool }
  | CMFire { fireTarget :: Pos }
  | CMChat { clientChatText :: String }
  | CMQuit
  deriving (Show, Generic)

instance ToJSON ClientMsg
instance FromJSON ClientMsg

data ServerMsg
  = SMWelcome { playerId :: Int, playerName :: String }
  | SMGamePhase { smPhase :: GamePhase }
  | SMYourTurn
  | SMBothReady
  | SMOpponentTurn
  | SMResult { res :: String, resTarget :: Pos, resOwner :: Int, resShipType :: Maybe String, resShipPositions :: Maybe [Pos] }
    -- "Hit","Miss","Sunk" and which player's board was affected. If a ship
    -- was sunk, resShipType contains the ship type name and resShipPositions the list of positions.
  | SMUpdateBoard { board :: Board }
  | SMGameOver { winner :: Int }
  | SMError { errorMsg :: String }
  | SMChat { fromPlayer :: Int, serverChatText :: String }
  | SMOpponentDisconnected
  deriving (Show, Generic)

instance ToJSON ServerMsg
instance FromJSON ServerMsg

encodeClientMsg :: ClientMsg -> BL.ByteString
encodeClientMsg = encode

decodeClientMsg :: BL.ByteString -> Maybe ClientMsg
decodeClientMsg = decode
