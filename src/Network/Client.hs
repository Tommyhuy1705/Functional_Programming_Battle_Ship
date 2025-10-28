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

runClient :: String -> String -> IO ()
runClient host port = NS.withSocketsDo $ do
  addr:_ <- NS.getAddrInfo Nothing (Just host) (Just port)
  sock <- NS.socket (NS.addrFamily addr) NS.Stream NS.defaultProtocol
  NS.connect sock (NS.addrAddress addr)
  putStrLn "Connected to server."
  -- spawn a receiver thread
  _ <- forkIO $ forever $ do
    bs <- NSB.recv sock 4096
    unless (BS.null bs) $ handleServerMsg bs
  -- main loop: read user input and send messages
  clientLoop sock

clientLoop :: NS.Socket -> IO ()
clientLoop sock = do
  putStrLn "Enter command (fire r c):"
  line <- getLine
  case words line of
    ["fire", r, c] ->
      let pos = (read r, read c)
          cm = CMFire pos
      in NSB.sendAll sock (BL.toStrict (encode cm)) >> clientLoop sock
    "quit":_ -> putStrLn "Bye"
    _ -> putStrLn "Unknown" >> clientLoop sock

handleServerMsg :: BS.ByteString -> IO ()
handleServerMsg bs = case decode (BL.fromStrict bs) :: Maybe ServerMsg of
  Nothing -> putStrLn ("Invalid server msg: " ++ show bs)
  Just sm -> print sm