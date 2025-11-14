module Config where

-- Cấu hình mạng
serverPort :: Int
serverPort = 8080

serverHost :: String
serverHost = "127.0.0.1"

-- Cấu hình game
boardWidth :: Int
boardWidth = 10

boardHeight :: Int
boardHeight = 10

-- Số lượng tối đa người chơi
maxPlayers :: Int
maxPlayers = 2

-- Timeout (giây)
turnTimeout :: Int
turnTimeout = 30

connectionTimeout :: Int
connectionTimeout = 60