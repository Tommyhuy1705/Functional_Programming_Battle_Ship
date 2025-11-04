{-# LANGUAGE OverloadedStrings #-}
module Network.Client (runClient) where

import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB
import Control.Concurrent
import Control.Monad (forever, unless)
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.ByteString as BS
import Network.Message
import Data.Aeson (encode, decode)
import Data.Char (toLower)

runClient :: String -> String -> IO ()
runClient host port = NS.withSocketsDo $ do
  addr:_ <- NS.getAddrInfo Nothing (Just host) (Just port)
  sock <- NS.socket (NS.addrFamily addr) NS.Stream NS.defaultProtocol
  NS.connect sock (NS.addrAddress addr)
  putStrLn "Connected to server."
  -- spawn a receiver thread
  _ <- forkIO $ forever $ do
    bs <- NSB.recv sock 4096
    unless (BS.null bs) $ do
      -- incoming data may contain multiple newline-delimited JSON messages
      let parts = BS.split 10 bs -- 10 == '\n'
      mapM_ handleServerMsg parts
  -- main loop: read user input and send messages
  clientLoop sock

clientLoop :: NS.Socket -> IO ()
clientLoop sock = do
  putStrLn "Enter command (fire r c) or (place id type r c orient) or (ready):"
  line <- getLine
  case words line of
    ["fire", r, c] -> do
      let pos = (read r, read c)
          cm = CMFire pos
      NSB.sendAll sock (BL.toStrict (encode cm <> BL.pack "\n"))
      clientLoop sock
    ["place", sid, stype, r, c, orient] -> do
      let sid' = read sid
          pos = (read r, read c)
          horiz = case map toLower orient of
                    "h" -> True
                    "horizontal" -> True
                    _ -> False
          cm = CMPlaceShip sid' stype pos horiz
      NSB.sendAll sock (BL.toStrict (encode cm <> BL.pack "\n"))
      clientLoop sock
    ["ready"] -> do
      NSB.sendAll sock (BL.toStrict (encode CMReady <> BL.pack "\n"))
      clientLoop sock
    "quit":_ -> putStrLn "Bye"
    _ -> putStrLn "Unknown" >> clientLoop sock

handleServerMsg :: BS.ByteString -> IO ()
handleServerMsg bs
  | BS.null bs = return ()
  | otherwise = case decode (BL.fromStrict bs) :: Maybe ServerMsg of
      Nothing -> putStrLn ("Invalid server msg: " ++ show bs)
      Just sm -> print sm