module Utils.Serializer where

import Data.Aeson
import Network.Message
import Game.State
import qualified Data.ByteString.Lazy.Char8 as BL

serializeGameState :: GameState -> String
serializeGameState gs = BL.unpack (encode gs)

deserializeGameState :: String -> Maybe GameState
deserializeGameState s = decode (BL.pack s)