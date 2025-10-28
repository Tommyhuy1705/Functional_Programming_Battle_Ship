{-# LANGUAGE NoRebindableSyntax #-}
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
{-# OPTIONS_GHC -w #-}
module PackageInfo_battleship (
    name,
    version,
    synopsis,
    copyright,
    homepage,
  ) where

import Data.Version (Version(..))
import Prelude

name :: String
name = "battleship"
version :: Version
version = Version [0,1,0] []

synopsis :: String
synopsis = ""
copyright :: String
copyright = "2025 Tommyhuy1705"
homepage :: String
homepage = "https://github.com/Tommyhuy1705/Functional_Programming_Battle_Ship#readme"
