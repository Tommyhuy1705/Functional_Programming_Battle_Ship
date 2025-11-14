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

-- Lưu session vào file nhỏ để giữ trạng thái đăng nhập giữa các lần chạy
sessionFile :: FilePath
sessionFile = "src/Database/.session"

-- Thử đăng nhập: trả về Right userId nếu thành công, Left lỗi nếu thất bại
login :: String -> String -> IO (Either String Int)
login username password = do
  mUser <- findUserByName username
  case mUser of
    Nothing -> return $ Left "User not found"
    Just u -> do
      ok <- verifyPassword u password
      if ok
        then do
          -- lưu session
          createDirectoryIfMissing True "src/Database"
          writeFile sessionFile (show (userId u))
          return $ Right (userId u)
        else return $ Left "Invalid password"

-- Đăng xuất: xoá file session nếu id trùng
logout :: Int -> IO ()
logout uid = do
  exists <- doesFileExist sessionFile
  whenExists <- return exists
  if whenExists
    then do
      -- đọc và so sánh
      content <- readFile sessionFile
      case reads content of
        ((n, _):_) | n == uid -> removeFile sessionFile
        _ -> return ()
    else return ()

-- Lấy session hiện tại (nếu có)
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
