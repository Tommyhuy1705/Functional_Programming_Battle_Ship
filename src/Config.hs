module Config where

-- Network configuration
serverPort :: Int
serverPort = 8080

serverHost :: String
serverHost = "127.0.0.1"

-- Game configuration
boardWidth :: Int
boardWidth = 10

boardHeight :: Int
boardHeight = 10

-- Maximum number of players
maxPlayers :: Int
maxPlayers = 2

-- Timeout values (in seconds)
turnTimeout :: Int
turnTimeout = 30

connectionTimeout :: Int
connectionTimeout = 60