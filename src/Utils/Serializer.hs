module Utils.Serializer where

import Data.Aeson
import Network.Message
import Game.State
import qualified Data.ByteString.Lazy.Char8 as BL

-- Mã hóa GameState thành JSON chuỗi
serializeGameState :: GameState -> String
serializeGameState gs = BL.unpack (encode gs)

-- Giải mã chuỗi JSON thành GameState
deserializeGameState :: String -> Maybe GameState
deserializeGameState s = decode (BL.pack s)