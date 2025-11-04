{-# LANGUAGE DeriveGeneric #-}
module Game.State
  ( PlayerState(..)
  , GameState(..)
  , initState
  , applyFire
  , placeShipForPlayer
  , getPlayerBoard
  , setPlayerReady
  , hasPlacedAllShips
  , setWinner
  )
where

import Game.Types
import Game.Board
import Game.Ship
import Game.Logic
import Network.Message (GamePhase(..))
import GHC.Generics (Generic)
import Data.Aeson (ToJSON, FromJSON)

data PlayerState = PlayerState
  { board :: Board
  , ships :: [Ship]
  , ready :: Bool
  } deriving (Show, Generic)

instance ToJSON PlayerState
instance FromJSON PlayerState

data GameState = GameState
  { p1 :: PlayerState
  , p2 :: PlayerState
  , turn :: Int -- 1 or 2
  , phase :: GamePhase
  , winner :: Maybe Int
  } deriving (Show, Generic)

instance ToJSON GameState
instance FromJSON GameState

initState :: GameState
initState = GameState 
  { p1 = PlayerState initBoard [] False
  , p2 = PlayerState initBoard [] False
  , turn = 1
  , phase = WaitingPlayers
  , winner = Nothing
  }

-- | Return the board for the given player id (1 or 2)
getPlayerBoard :: GameState -> Int -> Board
getPlayerBoard gs 1 = board (p1 gs)
getPlayerBoard gs 2 = board (p2 gs)
getPlayerBoard _ _ = error "getPlayerBoard: invalid player id"


-- | Try to place a Ship for a player. Returns Nothing if placement invalid.
placeShipForPlayer :: GameState -> Int -> Ship -> Maybe GameState
placeShipForPlayer gs pid ship
  | pid == 1 =
      let ps = p1 gs
          existingTypes = map shipType (ships ps)
      in if shipType ship `elem` existingTypes
           then Nothing
           else case placeShipOnBoard (board ps) ship of
             Nothing -> Nothing
             Just b' -> Just $ gs { p1 = ps { board = b', ships = ships ps ++ [ship] } }
  | pid == 2 =
      let ps = p2 gs
          existingTypes = map shipType (ships ps)
      in if shipType ship `elem` existingTypes
           then Nothing
           else case placeShipOnBoard (board ps) ship of
             Nothing -> Nothing
             Just b' -> Just $ gs { p2 = ps { board = b', ships = ships ps ++ [ship] } }
  | otherwise = Nothing

-- | Mark player ready. Returns updated GameState
setPlayerReady :: GameState -> Int -> GameState
setPlayerReady gs 1 = gs { p1 = (p1 gs) { ready = True } }
setPlayerReady gs 2 = gs { p2 = (p2 gs) { ready = True } }
setPlayerReady gs _ = gs

-- | Set the winner and transition to GameOver
setWinner :: GameState -> Int -> GameState
setWinner gs wid = gs { winner = Just wid, phase = GameOver }

-- | Check if player has placed all required ship types
requiredShipTypes :: [ShipType]
requiredShipTypes = [Carrier, Battleship, Cruiser, Submarine, Destroyer]

hasPlacedAllShips :: GameState -> Int -> Bool
hasPlacedAllShips gs pid =
  let st = if pid == 1 then ships (p1 gs) else ships (p2 gs)
      typesPlaced = map shipType st
  in all (`elem` typesPlaced) requiredShipTypes

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
