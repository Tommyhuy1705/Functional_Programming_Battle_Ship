module Utils.Concurrency where

import Control.Concurrent
import Control.Concurrent.MVar
import Game.State

type GameLock = MVar GameState

createGameLock :: GameState -> IO GameLock
createGameLock = newMVar

-- | Safely run an action that reads and updates the GameState.
-- The action receives the current GameState and returns (newState, result).
-- withGameLock returns the result and ensures the GameState is updated atomically.
withGameLock :: GameLock -> (GameState -> IO (GameState, a)) -> IO a
withGameLock lock action = modifyMVar lock $ \gs -> do
	(gs', a) <- action gs
	return (gs', a)