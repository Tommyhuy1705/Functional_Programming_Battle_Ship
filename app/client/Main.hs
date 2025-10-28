module Main where

import Network.Client (runClient)

main :: IO ()
main = runClient "127.0.0.1" "3000"
