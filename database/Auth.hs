module Database.Auth
  ( login
  , logout
  , currentSession
  ) where

-- Authentication helper skeletons. Implement session/token handling here.

login :: String -> String -> IO (Either String Int)
login username password = do
  -- TODO: verify credentials, create session, return userId
  return $ Left "Not implemented"

logout :: Int -> IO ()
logout uid = do
  -- TODO: remove session/token
  return ()

currentSession :: IO (Maybe Int)
currentSession = do
  -- TODO: return current session user id if any
  return Nothing
