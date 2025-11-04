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
import Game.Logic (ShotResult(..))
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
      CMFire { fireTarget = pos } -> do
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
              -- send notifications in parallel
              runParallel_ [ sendServer (clientSocket opp) (SMResult { res = show res, resTarget = pos })
                           , sendServer (clientSocket opp) (SMUpdateBoard { board = defBoard })
                           ]
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
startGame s = putStrLn "Starting game (placeholder)" >> return ()
