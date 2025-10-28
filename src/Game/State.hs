module Game.State
  ( GameState(..)
  , initState
  , applyFire
  )
where

import Game.Types
import Game.Board
import Game.Ship
import Game.Logic
import Network.Message (GamePhase(..))

data PlayerState = PlayerState
  { board :: Board
  , ships :: [Ship]
  } deriving (Show)

data GameState = GameState
  { p1 :: PlayerState
  , p2 :: PlayerState
  , turn :: Int -- 1 or 2
  , phase :: GamePhase
  , winner :: Maybe Int
  } deriving (Show)

initState :: GameState
initState = GameState 
  { p1 = PlayerState initBoard []
  , p2 = PlayerState initBoard []
  , turn = 1
  , phase = WaitingPlayers
  , winner = Nothing
  }

-- applyFire: player A fires at player B
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
