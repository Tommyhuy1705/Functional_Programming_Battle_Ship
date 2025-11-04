{-# LANGUAGE OverloadedStrings #-}
module Network.Server (runServer) where

import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB
import Control.Concurrent
import Control.Exception (bracket, finally, try, SomeException)
import Control.Monad (forever, when, unless)
import Utils.Concurrency (GameLock, createGameLock, withGameLock)
import Utils.Parallel (runParallel_)
import Data.Aeson (encode, decode)
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.ByteString as BS
import Network.Message
import Game.State
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
  when (pid == 1) $ sendServer sock SMYourTurn -- let player 1 start
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
      CMReady -> do
        -- mark this player ready
        _ <- withGameLock mstate $ \gs -> do
          let gs' = setPlayerReady gs pid
          return (gs', ())
        -- check if both ready and have placed all required ships
        gsAfter <- readMVar mstate
        let bothReady = ready (p1 gsAfter) && ready (p2 gsAfter)
            bothPlaced = hasPlacedAllShips gsAfter 1 && hasPlacedAllShips gsAfter 2
        when (bothReady && bothPlaced) $ do
          -- transition to Playing
          modifyMVar_ mstate $ \gs -> return $ gs { phase = Playing }
          clientsList <- readMVar (clients serverState)
          mapM_ (\c -> sendServer (clientSocket c) (SMGamePhase { smPhase = Playing })) clientsList
          -- notify whose turn it is
          gsNow <- readMVar mstate
          let t = turn gsNow
          case find (\c -> clientId c == t) clientsList of
            Just c -> sendServer (clientSocket c) SMYourTurn
            Nothing -> return ()

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
                else sendServer sock (SMError { errorMsg = "Placement conflicts with existing ships or duplicate ship type" })

      CMFire { fireTarget = pos } -> do
        -- enforce that the game is in Playing phase and it's this player's turn
        gsNow <- readMVar mstate
        if phase gsNow /= Playing
          then sendServer sock (SMError { errorMsg = "Game is not in playing phase" })
          else if turn gsNow /= pid
            then sendServer sock (SMError { errorMsg = "Not your turn" })
            else do
              -- apply fire to state using the game lock helper
              res <- withGameLock mstate $ \gs ->
                let (gs', res') = applyFire gs pid pos
                in return (gs', res')
              -- send result to firing client
              sendServer sock (SMResult { res = show res, resTarget = pos })
              -- notify opponent: find other client and send them the result and updated board
              clientsList <- readMVar (clients serverState)
              let mOpp = find (\c -> clientId c /= pid) clientsList
              case mOpp of
                Nothing -> return ()
                Just opp -> do
                  -- read updated game state to compute defender board
                  gs' <- readMVar mstate
                  let defBoard = if pid == 1 then getPlayerBoard gs' 2 else getPlayerBoard gs' 1
                      defenderShips = if pid == 1 then ships (p2 gs') else ships (p1 gs')
                  -- send notifications in parallel
                  runParallel_ [ sendServer (clientSocket opp) (SMResult { res = show res, resTarget = pos })
                               , sendServer (clientSocket opp) (SMUpdateBoard defBoard)
                               ]
                  -- check for game over (all defender ships sunk)
                  if allSunk defBoard defenderShips
                    then do
                      -- update game state: set winner and phase
                      modifyMVar_ mstate $ \gs -> return $ setWinner gs pid
                      -- broadcast game over to all clients
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
