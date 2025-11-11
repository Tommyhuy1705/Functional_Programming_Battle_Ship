{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}

module Network.Server (runServer) where

import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB
import Control.Concurrent
import Control.Exception (bracket, finally, try, SomeException)
import Control.Monad (forever, when, unless, forM_)

import Utils.Concurrency (GameLock, createGameLock, withGameLock)
import Utils.Parallel (runParallel_)
import Data.Aeson (encode, decode)
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.ByteString as BS
import Network.Message
import Game.State
import Game.Board (initBoard)
import Game.Types
import Game.Ship
import Game.Logic (ShotResult(..), allSunk)
import Data.List (find)

data Client = Client 
    { clientSocket :: NS.Socket
    , clientId :: Int
    , clientName :: String
    }

data ServerState = ServerState
    { gameState :: MVar GameState
    , clients :: MVar [Client]
    }

runServer :: String -> IO ()
runServer port = do
  addrinfos <- NS.getAddrInfo (Just (NS.defaultHints { NS.addrFlags = [NS.AI_PASSIVE] })) Nothing (Just port)
  let serveraddr = head addrinfos
  sock <- NS.socket (NS.addrFamily serveraddr) NS.Stream NS.defaultProtocol
  NS.setSocketOption sock NS.ReuseAddr 1
  NS.bind sock (NS.addrAddress serveraddr)
  NS.listen sock 2
  putStrLn $ "Server listening on port " ++ port
  mstate <- createGameLock initState
  mclients <- newMVar []
  let serverState = ServerState mstate mclients
  forever $ do
    (clientSock, _) <- NS.accept sock
    clients <- readMVar mclients
    if length clients >= 2
      then do
        putStrLn "Game full, rejecting connection"
        NS.close clientSock
      else do
        let clientId = length clients + 1
        putStrLn $ "Client " ++ show clientId ++ " connected"
        let client = Client clientSock clientId ("Player " ++ show clientId)
        modifyMVar_ mclients $ \cs -> return $ cs ++ [client]
        _ <- forkIO $ clientHandler client serverState `finally` handleDisconnect client serverState
        when (clientId == 2) $ startGame serverState

clientHandler :: Client -> ServerState -> IO ()
clientHandler client serverState = do
  let sock = clientSocket client
      pid  = clientId client
      mstate = gameState serverState
  sendServer sock (SMWelcome { playerId = pid, playerName = clientName client })
  let
    loop = do
      msgbs <- recvLine sock
      -- client closed socket => recv returns empty; end loop to allow cleanup
      if BS.null msgbs
        then return ()
        else do
          -- a single recv may contain multiple newline-delimited JSON messages
          let parts = filter (not . BS.null) $ BS.split 10 msgbs -- 10 == '\n'
          mapM_ (\p -> case decode (BL.fromStrict p) :: Maybe ClientMsg of
                          Nothing -> putStrLn $ "Invalid message: " ++ show p
                          Just cm -> handleClientMsg cm)
                parts
          loop

    handleClientMsg :: ClientMsg -> IO ()
    handleClientMsg cm = case cm of
      CMQuit -> do
        -- reset game to placing phase and clear boards/ships/ready flags
        modifyMVar_ mstate $ \_ -> return $ initState { phase = PlacingShips }
        -- notify clients to re-place ships and send empty boards
        cls <- readMVar (clients serverState)
        mapM_ (\c -> sendServer (clientSocket c) (SMGamePhase { smPhase = PlacingShips })) cls
        mapM_ (\c -> sendServer (clientSocket c) (SMUpdateBoard (getPlayerBoard initState (clientId c)))) cls
        putStrLn "Received CMQuit: resetting game to PlacingShips"

      CMReady -> do
        -- mark this player ready
        _ <- withGameLock mstate $ \gs -> do
          let gs' = setPlayerReady gs pid
          return (gs', ())
        -- check both ready and have placed all required ships
        gsAfter <- readMVar mstate
        let bothReady = ready (p1 gsAfter) && ready (p2 gsAfter)
            bothPlaced = hasPlacedAllShips gsAfter 1 && hasPlacedAllShips gsAfter 2
        when (bothReady && bothPlaced) $ do
          -- Bắt đầu trận đấu
          modifyMVar_ mstate $ \gs -> return $ gs { phase = Playing }

          clientsList <- readMVar (clients serverState)
          putStrLn "  Both players ready! Starting game..."

          -- Gửi thông báo bắt đầu cho cả hai
          mapM_ (\c -> sendServer (clientSocket c) (SMGamePhase { smPhase = Playing })) clientsList

          -- Gửi trạng thái lượt chơi rõ ràng
          let t = 1  -- mặc định Player 1 luôn bắt đầu
          forM_ clientsList $ \c ->
            if clientId c == t
              then sendServer (clientSocket c) SMYourTurn
              else sendServer (clientSocket c) SMOpponentTurn


      CMPlaceShip { psShipId = sid, psType = stype, psPos = pos, psHoriz = horiz } -> do
        case parseShipType stype of
          Nothing -> sendServer sock (SMError { errorMsg = "Unknown ship type: " ++ stype })
          Just sht -> case placeShipPositions pos horiz sht of
            Nothing -> sendServer sock (SMError { errorMsg = "Placement out of bounds" })
            Just poses -> do
              let ship = Ship { shipId = sid, shipType = sht, positions = poses }
              success <- withGameLock mstate $ \gs ->
                case placeShipForPlayer gs pid ship of
                  Nothing -> return (gs, False)
                  Just gs' -> return (gs', True)
              if success
                then do
                  -- return updated board for player
                  gs' <- readMVar mstate
                  sendServer sock (SMUpdateBoard (getPlayerBoard gs' pid))
                  -- After a successful placement, re-check if both players are ready AND both have placed all ships.
                  -- This handles the race where the client may have sent CMReady before the last CMPlaceShip
                  -- was processed by the server. If both conditions hold, start the game and notify clients.
                  let bothReady = ready (p1 gs') && ready (p2 gs')
                      bothPlaced = hasPlacedAllShips gs' 1 && hasPlacedAllShips gs' 2
                  when (bothReady && bothPlaced) $ do
                    modifyMVar_ mstate $ \gs -> return $ gs { phase = Playing }
                    clientsList' <- readMVar (clients serverState)
                    putStrLn "  Both players ready after placement! Starting game..."
                    mapM_ (\c -> sendServer (clientSocket c) (SMGamePhase { smPhase = Playing })) clientsList'
                    -- inform who has the turn (default player 1)
                    let t = 1
                    forM_ clientsList' $ \c ->
                      if clientId c == t
                        then sendServer (clientSocket c) SMYourTurn
                        else sendServer (clientSocket c) SMOpponentTurn
                else sendServer sock (SMError { errorMsg = "Placement conflicts with existing ships or duplicate ship type" })

      CMFire { fireTarget = pos } -> do
        putStrLn $ "[DEBUG] Player " ++ show pid ++ " fired at " ++ show pos
        gsNow <- readMVar mstate
        if phase gsNow /= Playing
          then sendServer sock (SMError { errorMsg = "Game is not in playing phase" })
          else if turn gsNow /= pid
            then sendServer sock (SMError { errorMsg = "Not your turn" })
            else do
              -- apply the fire under game lock and get the result
              res <- withGameLock mstate $ \gs ->
                let (gs', res') = applyFire gs pid pos
                in return (gs', res')
              putStrLn $ "[DEBUG] Fire result: " ++ show res
              let resTxt = case res of
                    ShotHit  -> "hit"
                    ShotMiss -> "miss"
                    ShotSunk _ -> "sunk"
              -- defender id (whose board was affected)
              let defenderId = if pid == 1 then 2 else 1

              -- read updated game state to compute defender board and ship list
              gs' <- readMVar mstate
              let defBoard = getPlayerBoard gs' defenderId
                  defenderShips = if defenderId == 1 then ships (p1 gs') else ships (p2 gs')

              -- if a ship was sunk, lookup its type and positions
              let (mShipType, mShipPositions) = case res of
                    ShotSunk sid -> case find (\s -> shipId s == sid) defenderShips of
                                      Just sh -> (Just (show (shipType sh)), Just (positions sh))
                                      Nothing -> (Nothing, Nothing)
                    _ -> (Nothing, Nothing)

              -- notify attacker with result (include sunk info if present)
              sendServer sock (SMResult { res = resTxt, resTarget = pos, resOwner = defenderId
                                        , resShipType = mShipType, resShipPositions = mShipPositions })

              -- notify opponent (defender) with same result and updated board
              clientsList <- readMVar (clients serverState)
              let mOpp = find (\c -> clientId c /= pid) clientsList
              case mOpp of
                Nothing -> return ()
                Just opp -> do
                  runParallel_ [ sendServer (clientSocket opp) (SMResult { res = resTxt, resTarget = pos, resOwner = defenderId
                                                                             , resShipType = mShipType, resShipPositions = mShipPositions })
                               , sendServer (clientSocket opp) (SMUpdateBoard defBoard)
                               ]

              -- check for game over (all defender ships sunk)
              if allSunk defBoard defenderShips
                then do
                  modifyMVar_ mstate $ \gs -> return $ setWinner gs pid
                  cls <- readMVar (clients serverState)
                  mapM_ (\c -> sendServer (clientSocket c) (SMGameOver pid)) cls
                  putStrLn $ "Player " ++ show pid ++ " has sunk all enemy ships. Mission completed!"
                else do
                  -- not game over: notify whose turn it is now
                  gsAfter <- readMVar mstate
                  let t = turn gsAfter
                  case find (\c -> clientId c == t) clientsList of
                    Just c -> sendServer (clientSocket c) SMYourTurn
                    Nothing -> return ()
      _ -> putStrLn $ "Unhandled client msg: " ++ show cm

  loop

sendServer :: NS.Socket -> ServerMsg -> IO ()
sendServer sock sm = NSB.sendAll sock (BL.toStrict (encode sm <> BL.pack "\n"))

recvLine :: NS.Socket -> IO BS.ByteString
recvLine sock = do
  eres <- try (NSB.recv sock 4096) :: IO (Either SomeException BS.ByteString)
  case eres of
    Left _ -> return BS.empty
    Right bs -> return bs

handleDisconnect :: Client -> ServerState -> IO ()
handleDisconnect client s = do
  modifyMVar_ (clients s) $ \cs -> do
    let cs' = filter (\c -> clientId c /= clientId client) cs
    return cs'
  putStrLn $ "Client disconnected: " ++ show (clientId client)

startGame :: ServerState -> IO ()
startGame s = do
  -- set phase to PlacingShips and notify all clients
  modifyMVar_ (gameState s) $ \gs -> return $ gs { phase = PlacingShips }
  clientsList <- readMVar (clients s)
  mapM_ (\c -> sendServer (clientSocket c) (SMGamePhase { smPhase = PlacingShips })) clientsList
  putStrLn "Starting game: entering PlacingShips phase"
