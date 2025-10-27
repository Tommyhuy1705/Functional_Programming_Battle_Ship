module Utils.Concurrency where

import Control.Concurrent
import Control.Concurrent.MVar
import Game.State

type GameLock = MVar GameState

createGameLock :: GameState -> IO GameLock
createGameLock = newMVar

withGameLock :: GameLock -> (GameState -> IO (GameState, a)) -> IO a
withGameLock lock action = undefined  -- TODO: Implement thread-safe game state modification