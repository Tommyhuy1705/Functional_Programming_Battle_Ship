{-# LANGUAGE DeriveGeneric #-}
module Network.Message
  ( ClientMsg(..)
  , ServerMsg(..)
  , encodeClientMsg
  , decodeClientMsg
  )
where

import GHC.Generics (Generic)
import Data.Aeson (ToJSON, FromJSON, encode, decode)
import qualified Data.ByteString.Lazy.Char8 as BL
import Game.Types (Pos)

data GamePhase = WaitingPlayers | PlacingShips | Playing | GameOver
  deriving (Show, Generic, Eq)

instance ToJSON GamePhase
instance FromJSON GamePhase

data ClientMsg
  = CMReady                    -- ready to start / placed ships
  | CMPlaceShip { psShipId :: Int, psType :: String, psPos :: Pos, psHoriz :: Bool }
  | CMFire { target :: Pos }
  | CMChat { message :: String }
  | CMQuit
  deriving (Show, Generic)

instance ToJSON ClientMsg
instance FromJSON ClientMsg

data ServerMsg
  = SMWelcome { playerId :: Int, playerName :: String }
  | SMGamePhase { phase :: GamePhase }
  | SMYourTurn
  | SMResult { res :: String, target :: Pos } -- "Hit","Miss","Sunk"
  | SMUpdateBoard { board :: Board }
  | SMGameOver { winner :: Int }
  | SMError { errorMsg :: String }
  | SMChat { fromPlayer :: Int, message :: String }
  | SMOpponentDisconnected
  deriving (Show, Generic)

instance ToJSON ServerMsg
instance FromJSON ServerMsg

encodeClientMsg :: ClientMsg -> BL.ByteString
encodeClientMsg = encode

decodeClientMsg :: BL.ByteString -> Maybe ClientMsg
decodeClientMsg = decode
