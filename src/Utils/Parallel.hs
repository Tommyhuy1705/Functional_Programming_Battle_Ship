module Utils.Parallel
  ( runParallel
  , runParallel_
  ) where

import Control.Concurrent.Async (mapConcurrently, mapConcurrently_)

-- | Chạy danh sách hành động IO song song và thu kết quả
-- Dùng 'mapConcurrently' để thực thi đồng thời
runParallel :: [IO a] -> IO [a]
runParallel = mapConcurrently id

-- | Chạy danh sách hành động IO song song, bỏ qua kết quả
runParallel_ :: [IO ()] -> IO ()
runParallel_ = mapConcurrently_ id
