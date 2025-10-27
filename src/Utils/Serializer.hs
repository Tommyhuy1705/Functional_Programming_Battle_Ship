module Utils.Serializer where

import Data.Aeson
import Network.Message
import Game.State

serializeGameState :: GameState -> String
serializeGameState = undefined  -- TODO: Implement game state serialization

deserializeGameState :: String -> Maybe GameState
deserializeGameState = undefined  -- TODO: Implement game state deserialization