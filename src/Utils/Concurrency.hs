module Utils.Concurrency where

import Control.Concurrent
import Control.Concurrent.MVar
import Game.State

type GameLock = MVar GameState

createGameLock :: GameState -> IO GameLock
createGameLock = newMVar

-- | Thực thi an toàn một hành động đọc/ghi GameState.
-- Hàm nhận GameState hiện tại và trả về (trạng thái mới, kết quả).
-- withGameLock trả về kết quả và đảm bảo cập nhật trạng thái nguyên tử.
withGameLock :: GameLock -> (GameState -> IO (GameState, a)) -> IO a
withGameLock lock action = modifyMVar lock $ \gs -> do
	(gs', a) <- action gs
	return (gs', a)