{-# LANGUAGE OverloadedStrings #-}
module Network.Server (runServer) where

import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB
import Control.Concurrent
import Control.Exception (bracket, finally)
import Control.Monad (forever, when, unless)
import Data.Aeson (encode, decode)
import qualified Data.ByteString.Lazy.Char8 as BL
import Network.Message
import Game.State
import Game.Types
import Game.Logic (ShotResult(..))

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
  mstate <- newMVar initState
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
        let client = Client clientSock clientId "Player " ++ show clientId
        modifyMVar_ mclients $ \cs -> return $ cs ++ [client]
        _ <- forkIO $ clientHandler client serverState `finally` handleDisconnect client serverState
        when (clientId == 2) $ startGame serverState

clientHandler :: NS.Socket -> Int -> MVar GameState -> IO ()
clientHandler sock pid mstate = do
  sendServer sock (SMWelcome ("You are player " ++ show pid))
  when (pid == 1) $ sendServer sock SMYourTurn -- let player 1 start
  loop
  where
    loop = do
      msgbs <- recvLine sock
      case decode (BL.fromStrict msgbs) :: Maybe ClientMsg of
        Nothing -> putStrLn "Invalid message"
        Just cm -> handleClientMsg cm
      loop

    handleClientMsg :: ClientMsg -> IO ()
    handleClientMsg cm = case cm of
      CMFire { target = pos } -> do
        -- apply fire to state
        gs <- takeMVar mstate
        let (gs', res) = applyFire gs pid pos
        putMVar mstate gs'
        sendServer sock (SMResult (show res))
        -- notify opponent
        -- In real code, maintain other socket references; here simplified
      _ -> putStrLn $ "Unhandled client msg: " ++ show cm

sendServer :: NS.Socket -> ServerMsg -> IO ()
sendServer sock sm = NSB.sendAll sock (BL.toStrict (encode sm))

recvLine :: NS.Socket -> IO NS.ByteString
recvLine sock = NSB.recv sock 4096
