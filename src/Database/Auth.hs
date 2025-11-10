module Database.Auth
  ( login
  , logout
  , currentSession
  ) where

import Database.Users
import Control.Monad (void)
import System.Directory (doesFileExist, removeFile, createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO (writeFile, readFile)
import Data.Maybe (fromMaybe)
import Data.IORef (newIORef)
import System.IO.Unsafe (unsafePerformIO)

sessionRef = unsafePerformIO (newIORef Nothing)

-- Persist session to a small file so the user stays logged in between runs.
sessionFile :: FilePath
sessionFile = "src/Database/.session"

-- Attempt to log in. Returns Right userId on success, Left error message otherwise.
login :: String -> String -> IO (Either String Int)
login username password = do
  mUser <- findUserByName username
  case mUser of
    Nothing -> return $ Left "User not found"
    Just u -> do
      ok <- verifyPassword u password
      if ok
        then do
          -- persist session
          createDirectoryIfMissing True "src/Database"
          writeFile sessionFile (show (userId u))
          return $ Right (userId u)
        else return $ Left "Invalid password"

logout :: Int -> IO ()
logout uid = do
  exists <- doesFileExist sessionFile
  whenExists <- return exists
  if whenExists
    then do
      -- try to read and compare
      content <- readFile sessionFile
      case reads content of
        ((n, _):_) | n == uid -> removeFile sessionFile
        _ -> return ()
    else return ()

currentSession :: IO (Maybe Int)
currentSession = do
  exists <- doesFileExist sessionFile
  if not exists
    then return Nothing
    else do
      content <- readFile sessionFile
      case reads content of
        ((n, _):_) -> return (Just n)
        _ -> return Nothing
