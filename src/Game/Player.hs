module Game.Player where

import Game.Board
import Game.Ship

data Player = Player {
    playerId :: Int,
    playerName :: String,
    playerBoard :: Board,
    ships :: [Ship],
    isReady :: Bool
}

initPlayer :: Int -> String -> Player
initPlayer id name = Player {
    playerId = id,
    playerName = name,
    playerBoard = initBoard,
    ships = [],
    isReady = False
}