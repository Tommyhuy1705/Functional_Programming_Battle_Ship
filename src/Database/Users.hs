{-# LANGUAGE ScopedTypeVariables #-}

module Database.Users
  ( User(..)
  , createUser
  , findUserByName
  , findUserById
  , verifyPassword
  ) where

import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.FromRow
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Base64 as B64
import qualified Crypto.KDF.PBKDF2 as PBKDF2
import Crypto.Hash.Algorithms (SHA256(SHA256))
import Crypto.Random (getRandomBytes)
import System.Environment (lookupEnv)
import Control.Exception (catch, SomeException)
import Data.String (fromString)
import Configuration.Dotenv (loadFile, defaultConfig)

--------------------------------------------------------------------------------
-- User type

data User = User
  { userId   :: Int
  , userName :: String
  , userHash :: String  -- stored as base64(salt) <> "$" <> base64(hash)
  } deriving (Show, Eq)

instance FromRow User where
  fromRow = User <$> field <*> field <*> field

--------------------------------------------------------------------------------
-- PBKDF2 parameters

iterations :: Int
iterations = 10000

dkLen :: Int
dkLen = 32

--------------------------------------------------------------------------------
-- PostgreSQL connection

getConn :: IO (Either String Connection)
getConn = do
  _ <- loadFile defaultConfig
  mUrl <- lookupEnv "DATABASE_URL"
  case mUrl of
    Just url -> do
      conn <- connectPostgreSQL (BSC.pack url)
      pure (Right conn)
    Nothing -> do
      mu    <- lookupEnv "user"
      mp    <- lookupEnv "password"
      mh    <- lookupEnv "host"
      mport <- lookupEnv "port"
      mdb   <- lookupEnv "dbname"
      case (mu, mp, mh, mport, mdb) of
        (Just u, Just p, Just h, Just port, Just db) -> do
          let connStr =
                "host=" ++ h ++
                " port=" ++ port ++
                " user=" ++ u ++
                " password=" ++ p ++
                " dbname=" ++ db
          conn <- connectPostgreSQL (BSC.pack connStr)
          pure (Right conn)
        _ -> pure (Left "DATABASE_URL not set and individual DB env vars missing")

--------------------------------------------------------------------------------
-- Ensure users table exists

ensureSchema :: IO ()
ensureSchema = do
  ec <- getConn
  case ec of
    Left _ -> pure ()
    Right conn -> do
      _ <- execute_ conn (fromString $
        "CREATE TABLE IF NOT EXISTS users (\
        \ id SERIAL PRIMARY KEY,\
        \ username TEXT NOT NULL UNIQUE,\
        \ password_hash TEXT NOT NULL,\
        \ created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
        )
      close conn

--------------------------------------------------------------------------------
-- Create a new user

createUser :: String -> String -> IO (Either String User)
createUser name password = do
  ensureSchema
  salt <- getRandomBytes 16
  let params = PBKDF2.Parameters
        { PBKDF2.iterCounts = iterations
        , PBKDF2.outputLength = dkLen
        }
      dk = PBKDF2.generate (PBKDF2.prfHMAC SHA256) params (BSC.pack password) salt
      stored = BSC.unpack (B64.encode salt) ++ "$" ++ BSC.unpack (B64.encode dk)
  ec <- getConn
  case ec of
    Left err -> pure (Left err)
    Right conn -> do
      let q = fromString "INSERT INTO users (username, password_hash) VALUES (?, ?)"
      r <- (execute conn q (name, stored) >> pure (Right ()))
        `catch` \(e :: SomeException) -> pure (Left (show e))
      close conn
      case r of
        Left errMsg -> pure (Left errMsg)
        Right () -> do
          m <- findUserByName name
          case m of
            Just u  -> pure (Right u)
            Nothing -> pure (Left "Failed to retrieve created user")

--------------------------------------------------------------------------------
-- Find user by username or id

findUserByName :: String -> IO (Maybe User)
findUserByName name = do
  ensureSchema
  ec <- getConn
  case ec of
    Left _ -> pure Nothing
    Right conn -> do
      rows <- query conn
        (fromString "SELECT id, username, password_hash FROM users WHERE username = ? LIMIT 1")
        (Only name) :: IO [User]
      close conn
      pure $ case rows of
        (u:_) -> Just u
        _     -> Nothing

findUserById :: Int -> IO (Maybe User)
findUserById uid = do
  ensureSchema
  ec <- getConn
  case ec of
    Left _ -> pure Nothing
    Right conn -> do
      rows <- query conn
        (fromString "SELECT id, username, password_hash FROM users WHERE id = ? LIMIT 1")
        (Only uid) :: IO [User]
      close conn
      pure $ case rows of
        (u:_) -> Just u
        _     -> Nothing

--------------------------------------------------------------------------------
-- Verify password

verifyPassword :: User -> String -> IO Bool
verifyPassword user password = do
  let stored = userHash user
      (saltB64, rest) = break (== '$') stored
  if null rest
    then pure False
    else do
      let hashB64 = drop 1 rest
          mSalt = B64.decode (BSC.pack saltB64)
          mHash = B64.decode (BSC.pack hashB64)
      case (mSalt, mHash) of
        (Right salt, Right expected) -> do
          let params = PBKDF2.Parameters
                { PBKDF2.iterCounts = iterations
                , PBKDF2.outputLength = dkLen
                }
              dk = PBKDF2.generate (PBKDF2.prfHMAC SHA256) params (BSC.pack password) salt
          pure (dk == expected)
        _ -> pure False
