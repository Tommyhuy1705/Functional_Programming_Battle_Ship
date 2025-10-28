module Main where

import Network.Server (runServer)
import Network.Socket (withSocketsDo)

main :: IO ()
main = withSocketsDo $ runServer "3000"
