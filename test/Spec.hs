module Main where

-- Một số module test có main riêng. Để đơn giản, ta import các module đó
-- và gọi các main theo thứ tự.

import qualified GameLogicSpec
import qualified NetworkSpec

main :: IO ()
main = do
	GameLogicSpec.main
	NetworkSpec.main
