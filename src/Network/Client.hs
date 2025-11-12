{-# LANGUAGE OverloadedStrings #-}
module Network.Client (runClient) where

import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB
import Control.Concurrent
import Control.Monad (forever, unless, void)
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.ByteString as BS
import Data.Aeson (encode, decode)
import Data.Char (toLower, toUpper)

import Network.Message

--------------------------------------------------------------------------------
-- Main entry point
--------------------------------------------------------------------------------
runClient :: String -> String -> IO ()
runClient host port = NS.withSocketsDo $ do
  addr:_ <- NS.getAddrInfo Nothing (Just host) (Just port)
  sock <- NS.socket (NS.addrFamily addr) NS.Stream NS.defaultProtocol
  NS.connect sock (NS.addrAddress addr)
  putStrLn "Connected to server."

  -- Spawn a listener thread to handle messages from server
  _ <- forkIO $ receiverLoop sock

  -- Enter interactive loop
  clientLoop sock

--------------------------------------------------------------------------------
-- Listen to server messages continuously
--------------------------------------------------------------------------------
receiverLoop :: NS.Socket -> IO ()
receiverLoop sock = forever $ do
  bs <- NSB.recv sock 4096
  if BS.null bs
    then do
      putStrLn "Server closed connection. (Socket empty)"
      threadDelay (2 * 1000000)
    else do
      putStrLn $ "[DEBUG] Raw data received: " ++ show bs
      let parts = filter (not . BS.null) $ BS.split 10 bs
      mapM_ handleServerMsg parts

--------------------------------------------------------------------------------
-- CLI command loop
--------------------------------------------------------------------------------
clientLoop :: NS.Socket -> IO ()
clientLoop sock = do
  putStrLn "\nEnter command:"
  putStrLn "  fire r c"
  putStrLn "  place id type r c orient"
  putStrLn "  ready"
  putStrLn "  rematch"
  putStrLn "  quit"
  line <- getLine
  case words line of
    ["fire", r, c] -> do
      let pos = (read r, read c)
      sendMsg sock (CMFire pos)
      clientLoop sock

    ["place", sid, stype, r, c, orient] -> do
      let sid'  = read sid
          pos   = (read r, read c)
          horiz = case map toLower orient of
                    "h" -> True
                    "horizontal" -> True
                    _ -> False
      sendMsg sock (CMPlaceShip sid' stype pos horiz)
      clientLoop sock

    ["ready"] -> do
      sendMsg sock CMReady
      clientLoop sock

    ["rematch"] -> do
      sendMsg sock CMRequestRematch
      putStrLn "Sent rematch request to server."
      clientLoop sock

    "quit":_ -> do
      sendMsg sock CMQuit
      putStrLn "Disconnected."
      NS.close sock

    _ -> putStrLn "Unknown command" >> clientLoop sock

--------------------------------------------------------------------------------
-- Handle messages from server
--------------------------------------------------------------------------------
handleServerMsg :: BS.ByteString -> IO ()
handleServerMsg bs
  | BS.null bs = return ()
  | otherwise  = do
      case decode (BL.fromStrict bs) :: Maybe ServerMsg of
        Nothing -> putStrLn ("Invalid server message: " ++ show bs)
        Just sm -> case sm of
          SMWelcome pid name ->
            putStrLn $ "Welcome, " ++ name ++ "! You are player " ++ show pid

          SMGamePhase ph ->
            putStrLn $ "Game phase: " ++ show ph

          SMYourTurn ->
            putStrLn "It's your turn! Type: fire r c"

          SMUpdateBoard _ ->
            putStrLn "[Board updated]"

          SMResult { res = r, resTarget = (x, y), resOwner = owner } ->
            putStrLn $ "Fired at (" ++ show x ++ "," ++ show y ++ "): "
                     ++ map toUpper r ++ " (board owner: " ++ show owner ++ ")"

          SMGameOver winner ->
            putStrLn $ "Game Over! Winner: Player " ++ show winner

          SMRematchRequested { fromPlayer = pid } ->
            putStrLn $ "Opponent Player " ++ show pid ++ " requested a rematch. Type 'rematch' to accept."

          SMRematchAccepted ->
            putStrLn "Rematch accepted by both players! Place your ships again."

          SMRematchDeclined ->
            putStrLn "Opponent declined rematch. Waiting for new player..."

          SMError { errorMsg = e } ->
            putStrLn $ "Error: " ++ e

          _ -> putStrLn $ "[Unhandled] " ++ show sm

--------------------------------------------------------------------------------
-- Helper to send client message
--------------------------------------------------------------------------------
sendMsg :: NS.Socket -> ClientMsg -> IO ()
sendMsg sock msg = do
  let payload = BL.toStrict (encode msg <> BL.pack "\n")
  putStrLn $ "[SEND] " ++ show msg
  NSB.sendAll sock payload
