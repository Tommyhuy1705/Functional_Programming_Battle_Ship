module Utils.Parallel
  ( runParallel
  , runParallel_
  ) where

import Control.Concurrent.Async (mapConcurrently, mapConcurrently_)

-- | Run a list of IO actions in parallel and collect results
-- This uses 'mapConcurrently' with the identity function.
runParallel :: [IO a] -> IO [a]
runParallel = mapConcurrently id

-- | Run a list of IO actions in parallel and ignore results
runParallel_ :: [IO ()] -> IO ()
runParallel_ = mapConcurrently_ id
