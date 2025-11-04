module Database.Users
  ( User(..)
  , createUser
  , findUserByName
  , verifyPassword
  ) where

-- Skeleton for user persistence. Implement with your chosen DB backend.

data User = User
  { userId :: Int
  , userName :: String
  , userHash :: String -- password hash
  } deriving (Show, Eq)

createUser :: String -> String -> IO (Either String User)
createUser name password = do
  -- TODO: hash password, insert into DB, return created User
  return $ Left "Not implemented"

findUserByName :: String -> IO (Maybe User)
findUserByName name = do
  -- TODO: query DB for user by name
  return Nothing

verifyPassword :: User -> String -> IO Bool
verifyPassword user password = do
  -- TODO: verify password against stored hash (bcrypt/argon2)
  return False
