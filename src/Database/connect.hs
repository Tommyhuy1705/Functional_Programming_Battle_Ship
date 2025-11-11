{-# LANGUAGE OverloadedStrings #-}

module Connect
  ( getConnection
  , testConnection
  ) where

import Database.PostgreSQL.Simple
import System.Environment (lookupEnv)
import qualified Data.ByteString.Char8 as BSC
import Control.Exception (try, SomeException)
import Data.Maybe (fromMaybe)
import Data.Functor ((<&>))
import Configuration.Dotenv (loadFile, defaultConfig)  -- 👈 thêm dotenv
import Control.Monad (void)
import Data.Maybe (fromMaybe)
import Data.List (intercalate)

-- | Load .env file at startup
loadEnvFile :: IO ()
loadEnvFile = do
  _ <- loadFile defaultConfig  -- Load biến môi trường từ .env (nếu có)
  return ()

-- | Helper to safely get environment variable (both lowercase & uppercase)
getEnvVar :: String -> IO (Maybe String)
getEnvVar key = do
  v1 <- lookupEnv key
  v2 <- lookupEnv (map toUpper key)
  return (v1 <|> v2)
  where toUpper c = if c >= 'a' && c <= 'z' then toEnum (fromEnum c - 32) else c

-- | Build connection string automatically
buildConnStr :: IO (Either String BSC.ByteString)
buildConnStr = do
  loadEnvFile  -- 👈 Gọi load dotenv trước
  mUrl <- lookupEnv "DATABASE_URL"
  case mUrl of
    Just url -> return $ Right (BSC.pack url)
    Nothing -> do
      mu <- getEnvVar "user"
      mp <- getEnvVar "password"
      mh <- getEnvVar "host"
      mport <- getEnvVar "port"
      mdb <- getEnvVar "dbname"
      case (mu, mp, mh, mport, mdb) of
        (Just u, Just p, Just h, Just port, Just db) -> do
          let connStr = intercalate " "
                [ "host=" ++ h
                , "port=" ++ port
                , "user=" ++ u
                , "password=" ++ p
                , "dbname=" ++ db
                ]
          return $ Right (BSC.pack connStr)
        _ -> return $ Left "❌ Missing required database environment variables."

-- | Open a PostgreSQL connection
getConnection :: IO (Either String Connection)
getConnection = do
  connStrResult <- buildConnStr
  case connStrResult of
    Left err -> return $ Left err
    Right connStr -> do
      result <- try (connectPostgreSQL connStr) :: IO (Either SomeException Connection)
      case result of
        Left e -> return $ Left ("❌ Failed to connect: " ++ show e)
        Right conn -> return $ Right conn

-- | Simple test function
testConnection :: IO ()
testConnection = do
  putStrLn "Attempting database connection..."
  result <- getConnection
  case result of
    Left err -> putStrLn err
    Right conn -> do
      putStrLn "✅ Connection successful!"
      [Only now] <- query_ conn "SELECT NOW();" :: IO [Only String]
      putStrLn ("Current Time: " ++ now)
      close conn
      putStrLn "🔒 Connection closed."
