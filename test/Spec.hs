module Main where

-- Some existing test modules define their own 'main'. To keep the
-- test runner simple we import those modules and invoke their mains
-- sequentially.

import qualified GameLogicSpec
import qualified NetworkSpec

main :: IO ()
main = do
	GameLogicSpec.main
	NetworkSpec.main
