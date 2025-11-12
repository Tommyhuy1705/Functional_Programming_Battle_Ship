{-# LANGUAGE DeriveGeneric #-}
module Game.State
  ( GameState(..)
  , PlayerState(..)
  , initState
  , applyFire
  , getPlayerBoard
  , placeShipsForPlayer
  , placeShipForPlayer
  , setPlayerReady
  , hasPlacedAllShips
  , setWinner
  , emptyBoard 
  , GamePhase(..)
  ) where

import Game.Types
import Game.Board
import Game.Ship
import Game.Logic
import Network.Message (GamePhase(..))
import GHC.Generics (Generic)
import Data.Aeson (ToJSON, FromJSON)
import Debug.Trace (trace)

-- | Trạng thái của một người chơi
data PlayerState = PlayerState
  { board :: Board
  , ships :: [Ship]
  , ready :: Bool
  } deriving (Show, Generic)

instance ToJSON PlayerState
instance FromJSON PlayerState

-- | Trạng thái toàn cục của trò chơi
data GameState = GameState
  { p1 :: PlayerState
  , p2 :: PlayerState
  , turn :: Int -- 1 hoặc 2
  , phase :: GamePhase
  , winner :: Maybe Int
  } deriving (Show, Generic)

instance ToJSON GameState
instance FromJSON GameState

-- | Khởi tạo game mới
initState :: GameState
initState = GameState
  { p1 = PlayerState initBoard [] False
  , p2 = PlayerState initBoard [] False
  , turn = 1
  , phase = WaitingPlayers
  , winner = Nothing
  }

-- | Lấy board của người chơi (1 hoặc 2)
getPlayerBoard :: GameState -> Int -> Board
getPlayerBoard gs 1 = board (p1 gs)
getPlayerBoard gs 2 = board (p2 gs)
getPlayerBoard _ _ = error "getPlayerBoard: invalid player id"

-- | Người chơi bắn vào đối thủ
applyFire :: GameState -> Int -> Pos -> (GameState, ShotResult)
applyFire gs attacker pos
  | attacker == 1 =
      let defender = p2 gs
          (b', res) = fireAt (board defender) (ships defender) pos
          def' = defender { board = b' }
          gs' = gs { p2 = def', turn = if res == ShotMiss then 2 else 1 }
      in (gs', res)
  | otherwise =
      let defender = p1 gs
          (b', res) = fireAt (board defender) (ships defender) pos
          def' = defender { board = b' }
          gs' = gs { p1 = def', turn = if res == ShotMiss then 1 else 2 }
      in (gs', res)

-- | Đặt danh sách tàu cho người chơi (dùng khi setup tự động)
placeShipsForPlayer :: GameState -> Int -> [Ship] -> Maybe GameState
placeShipsForPlayer gs player newShips =
  let playerState = if player == 1 then p1 gs else p2 gs
      baseBoard = board playerState
      -- đặt từng tàu một
      go b [] = Just b
      go b (s:ss) =
        case placeShipOnBoard b s of
          Nothing -> trace ("[ERROR] Không thể đặt tàu: " ++ show s) Nothing
          Just b' -> go b' ss
  in case go baseBoard newShips of
       Nothing -> Nothing
       Just finalBoard ->
         let newPlayerState = playerState { board = finalBoard, ships = newShips }
         in if player == 1
            then Just gs { p1 = newPlayerState }
            else Just gs { p2 = newPlayerState }

-- | Đặt từng tàu cho người chơi (thường dùng khi người chơi click chuột để đặt)
placeShipForPlayer :: GameState -> Int -> Ship -> Maybe GameState
placeShipForPlayer gs player ship =
  let playerState = if player == 1 then p1 gs else p2 gs
      b = board playerState
      currentShips = ships playerState
  in trace ("[DEBUG] Player " ++ show player ++ " đang đặt tàu: " ++ show ship) $
     case placeShipOnBoard b ship of
       Nothing -> trace "[ERROR] Failed to place ship (va chạm hoặc vượt biên)" Nothing
       Just b' ->
         let newPlayerState = playerState { board = b', ships = currentShips ++ [ship] }
         in trace "[OK] Đặt tàu thành công!" $
            if player == 1
            then Just gs { p1 = newPlayerState }
            else Just gs { p2 = newPlayerState }



-- | Đánh dấu người chơi đã sẵn sàng
setPlayerReady :: GameState -> Int -> GameState
setPlayerReady gs player =
  if player == 1
  then gs { p1 = (p1 gs) { ready = True } }
  else gs { p2 = (p2 gs) { ready = True } }

-- | Kiểm tra người chơi đã đặt đủ tàu chưa (ít nhất 5)
hasPlacedAllShips :: GameState -> Int -> Bool
hasPlacedAllShips gs player =
  let ss = if player == 1 then ships (p1 gs) else ships (p2 gs)
  in length ss >= 5

-- | Đặt người thắng
setWinner :: GameState -> Int -> GameState
setWinner gs pid = gs { winner = Just pid, phase = GameOver }

-- | Bàn cờ trống 10x10 (tương tự initBoard)
emptyBoard :: Board
emptyBoard = initBoard

