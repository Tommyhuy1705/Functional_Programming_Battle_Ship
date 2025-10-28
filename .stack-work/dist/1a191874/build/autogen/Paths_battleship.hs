{-# LANGUAGE CPP #-}
{-# LANGUAGE NoRebindableSyntax #-}
#if __GLASGOW_HASKELL__ >= 810
{-# OPTIONS_GHC -Wno-prepositive-qualified-module #-}
#endif
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
{-# OPTIONS_GHC -w #-}
module Paths_battleship (
    version,
    getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir,
    getDataFileName, getSysconfDir
  ) where


import qualified Control.Exception as Exception
import qualified Data.List as List
import Data.Version (Version(..))
import System.Environment (getEnv)
import Prelude


#if defined(VERSION_base)

#if MIN_VERSION_base(4,0,0)
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#else
catchIO :: IO a -> (Exception.Exception -> IO a) -> IO a
#endif

#else
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#endif
catchIO = Exception.catch

version :: Version
version = Version [0,1,0] []

getDataFileName :: FilePath -> IO FilePath
getDataFileName name = do
  dir <- getDataDir
  return (dir `joinFileName` name)

getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir, getSysconfDir :: IO FilePath




bindir, libdir, dynlibdir, datadir, libexecdir, sysconfdir :: FilePath
bindir     = "D:\\Study\\Project\\Functional_Programming_Battle_Ship\\.stack-work\\install\\ec9704e6\\bin"
libdir     = "D:\\Study\\Project\\Functional_Programming_Battle_Ship\\.stack-work\\install\\ec9704e6\\lib\\x86_64-windows-ghc-9.10.3-b42a\\battleship-0.1.0-9mbef3Ec1T8J5GsiNi72K8"
dynlibdir  = "D:\\Study\\Project\\Functional_Programming_Battle_Ship\\.stack-work\\install\\ec9704e6\\lib\\x86_64-windows-ghc-9.10.3-b42a"
datadir    = "D:\\Study\\Project\\Functional_Programming_Battle_Ship\\.stack-work\\install\\ec9704e6\\share\\x86_64-windows-ghc-9.10.3-b42a\\battleship-0.1.0"
libexecdir = "D:\\Study\\Project\\Functional_Programming_Battle_Ship\\.stack-work\\install\\ec9704e6\\libexec\\x86_64-windows-ghc-9.10.3-b42a\\battleship-0.1.0"
sysconfdir = "D:\\Study\\Project\\Functional_Programming_Battle_Ship\\.stack-work\\install\\ec9704e6\\etc"

getBinDir     = catchIO (getEnv "battleship_bindir")     (\_ -> return bindir)
getLibDir     = catchIO (getEnv "battleship_libdir")     (\_ -> return libdir)
getDynLibDir  = catchIO (getEnv "battleship_dynlibdir")  (\_ -> return dynlibdir)
getDataDir    = catchIO (getEnv "battleship_datadir")    (\_ -> return datadir)
getLibexecDir = catchIO (getEnv "battleship_libexecdir") (\_ -> return libexecdir)
getSysconfDir = catchIO (getEnv "battleship_sysconfdir") (\_ -> return sysconfdir)



joinFileName :: String -> String -> FilePath
joinFileName ""  fname = fname
joinFileName "." fname = fname
joinFileName dir ""    = dir
joinFileName dir fname
  | isPathSeparator (List.last dir) = dir ++ fname
  | otherwise                       = dir ++ pathSeparator : fname

pathSeparator :: Char
pathSeparator = '\\'

isPathSeparator :: Char -> Bool
isPathSeparator c = c == '/' || c == '\\'
