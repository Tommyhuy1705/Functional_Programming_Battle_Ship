{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE ScopedTypeVariables #-}


module Main where
import Data.Char (toLower)
import Data.List (isInfixOf)

import qualified Database.Users as Users
import qualified Database.Auth as Auth

import Control.Exception (try, SomeException)

-- Threepenny GUI
import qualified Graphics.UI.Threepenny as UI
import Graphics.UI.Threepenny.Core

-- Networking
import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB
import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forever, unless, void, when, forM_, forM)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson (encode, decode)

-- Game modules (của bạn)
import qualified Game.State as G
import qualified Game.Board as B
import qualified Game.Types as T
import qualified Game.Ship as S
import qualified Game.Logic as L
import Network.Message

-- Misc
import Data.IORef
import System.Random (randomRIO)
import Data.Maybe (fromMaybe, listToMaybe, isNothing)
import Data.Foldable (traverse_)

--------------------------------------------------------------------------------
-- Game environment (mở rộng với socket ref)
--------------------------------------------------------------------------------
data GameEnv = GameEnv
  { appWindow     :: Window
  , gameStateRef  :: IORef G.GameState
  , loggedInUsers :: IORef [(Int, String)]
  , sockRef       :: IORef (Maybe NS.Socket)
  , p1CellsRef    :: IORef [[Element]]        -- thêm
  , p2CellsRef    :: IORef [[Element]]        -- thêm
  , gameViewElem  :: IORef (Maybe Element)    -- thêm
  , playerIdRef   :: IORef (Maybe Int)        -- local player id assigned by server
  , sunkPositionsRef :: IORef [(Int, [T.Pos])] -- map owner -> sunk positions known to this client
  , targetMarksRef :: IORef [(Int, [((Int,Int), String)])] -- owner -> list of ((r,c), markType) for target grid (hit/miss/sunk)
  , loginViewElem :: IORef (Maybe Element)    -- login view element
  }


--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------
main :: IO ()
main = do
    putStrLn "Starting Battleship GUI..."
    putStrLn "Serving static from: app/gui/static (must contain style.css)"
    let config = defaultConfig
            { jsPort   = Just 8023
            , jsStatic = Just "app/gui/static"
            }
    startGUI config setup

--------------------------------------------------------------------------------
-- Setup: tạo UI, cố gắng kết nối server và start listener
--------------------------------------------------------------------------------
setup :: Window -> UI ()
setup window = do
    void $ return window # set UI.title "Battleship (Threepenny GUI)"
    void $ UI.addStyleSheet window "style.css"

    -- state
    gsRef <- liftIO $ newIORef G.initState
    usersRef <- liftIO $ newIORef ([] :: [(Int, String)])
    sockR <- liftIO $ newIORef Nothing

    -- tạo các IORef cho view và cells
    p1CellsRef <- liftIO $ newIORef ([] :: [[Element]])
    p2CellsRef <- liftIO $ newIORef ([] :: [[Element]])
    gameViewElem <- liftIO $ newIORef (Nothing :: Maybe Element)
    playerIdRef <- liftIO $ newIORef (Nothing :: Maybe Int)
    sunkPositionsRef <- liftIO $ newIORef ([] :: [(Int, [T.Pos])])
    targetMarksRef <- liftIO $ newIORef ([] :: [(Int, [((Int,Int), String)])])
    loginViewElem <- liftIO $ newIORef (Nothing :: Maybe Element)

    -- tạo environment hoàn chỉnh
    let env = GameEnv
          { appWindow     = window
          , gameStateRef  = gsRef
          , loggedInUsers = usersRef
          , sockRef       = sockR
          , p1CellsRef    = p1CellsRef
          , p2CellsRef    = p2CellsRef
          , gameViewElem  = gameViewElem
          , playerIdRef   = playerIdRef
          , sunkPositionsRef = sunkPositionsRef
          , targetMarksRef = targetMarksRef
          , loginViewElem = loginViewElem
          }

    -- tạo view
    loginView <- createLoginView env p1CellsRef p2CellsRef
    liftIO $ writeIORef loginViewElem (Just loginView)
    gameView <- createGameView env p1CellsRef p2CellsRef
    liftIO $ writeIORef gameViewElem (Just gameView)
    hideElement gameView

    -- attach các view vào body
    void $ getBody window #+ [element loginView, element gameView]

    -- kết nối đến server (background)
    let host = "127.0.0.1"
        port = "3000"
    liftIO $ do
      putStrLn $ "Attempting to connect to server " ++ host ++ ":" ++ port
      -- start background connection attempt (ignore ThreadId)
      void $ forkIO $ tryConnectAndListen env host port
    return ()


--------------------------------------------------------------------------------
-- Kết nối tới server và listener loop
--------------------------------------------------------------------------------
tryConnectAndListen :: GameEnv -> String -> String -> IO ()
tryConnectAndListen env host port = NS.withSocketsDo $ do
    eres <- tryConnect host port
    case eres of
      Left err -> putStrLn $ "Network: failed to connect: " ++ err
      Right sock -> do
          putStrLn "Network: connected to server"
          writeIORef (sockRef env) (Just sock)
          -- start listener loop: nhận newline-delimited JSON messages
          forever $ do
            bs <- NSB.recv sock 4096
            if BS.null bs
              then do
                putStrLn "Network: server closed connection"
                writeIORef (sockRef env) Nothing
                -- stop loop
                threadDelay (1 * 1000000)
              else do
                let parts = filter (not . BS.null) $ BS.split 10 bs -- split on '\n'
                forM_ parts $ \part -> case decode (BL.fromStrict part) :: Maybe ServerMsg of
                  Nothing -> putStrLn $ "Network: invalid server message: " ++ show part
                  Just sm -> handleServerMsgIO env sm

-- Try connect, return Left errorStr or Right sock
tryConnect :: String -> String -> IO (Either String NS.Socket)
tryConnect host port = do
    eres <- try $ do
      addr:_ <- NS.getAddrInfo Nothing (Just host) (Just port)
      sock <- NS.socket (NS.addrFamily addr) NS.Stream NS.defaultProtocol
      NS.connect sock (NS.addrAddress addr)
      return sock
    case eres of
      Left (e :: SomeException) -> return $ Left (show e)
      Right sock -> return $ Right sock

--------------------------------------------------------------------------------
-- Xử lý ServerMsg (được chạy trong IO thread)
-- Chúng ta cần cập nhật gameStateRef và sau đó yêu cầu UI re-render
--------------------------------------------------------------------------------
handleServerMsgIO :: GameEnv -> ServerMsg -> IO ()
handleServerMsgIO env msg = case msg of

  ---------------------------------------------------
  -- ⚙️ Game phase (Waiting, Placing, Playing, ...)
  ---------------------------------------------------
  SMGamePhase { smPhase = ph } -> do
    modifyIORef' (gameStateRef env) $ \gs -> gs { G.phase = ph }
    let wnd = appWindow env
    void $ runUI wnd $ do
      mGV <- liftIO $ readIORef (gameViewElem env)
      case mGV of
        Nothing -> return ()
        Just gv -> do
          gs <- liftIO $ readIORef (gameStateRef env)
          p1Cells <- liftIO $ readIORef (p1CellsRef env)
          p2Cells <- liftIO $ readIORef (p2CellsRef env)
          renderAllBoards env gv p1Cells p2Cells gs

          statusDiv <- getElementById wnd "status-msg"
          case statusDiv of
            Nothing -> return ()
            Just st -> do
              case ph of
                G.WaitingPlayers ->
                  void $ element st # set text "Waiting for another player..."
                G.PlacingShips ->
                  void $ element st # set text "Place your ships!"
                G.Playing -> do
                  let t = G.turn gs
                  if t == 1
                    then void $ element st # set text "Both players ready! Your turn!"
                                         # set UI.style [("color", "lime"), ("font-weight", "bold")]
                    else void $ element st # set text "Both players ready! Opponent's turn."
                                           # set UI.style [("color", "gray")]
                G.GameOver ->
                  void $ element st # set text "Game Over!"
                _ -> return ()

  ---------------------------------------------------
  -- 🧭 Lượt chơi
  ---------------------------------------------------
  SMYourTurn -> do
    let wnd = appWindow env
    void $ runUI wnd $ do
      statusDiv <- getElementById wnd "status-msg"
      maybe (return ()) (\st ->
        void $ element st # set text " Your turn!"
                          # set UI.style [("color", "lime"), ("font-weight", "bold")]
        ) statusDiv

  SMOpponentTurn -> do
    let wnd = appWindow env
    void $ runUI wnd $ do
      statusDiv <- getElementById wnd "status-msg"
      maybe (return ()) (\st ->
        void $ element st # set text " Opponent’s turn..."
                          # set UI.style [("color", "gray"), ("font-weight", "normal")]
        ) statusDiv

  ---------------------------------------------------
  -- 🎯 Kết quả bắn
  ---------------------------------------------------
  SMResult { res = r, resTarget = (x, y), resOwner = owner, resShipType = mShipType, resShipPositions = mShipPositions } -> do
    putStrLn $ "Server: fire result at (" ++ show x ++ "," ++ show y ++ "): " ++ r ++ " (owner=" ++ show owner ++ ")"
    let lower = map toLower r
    let isHit  = any (`isInfixOf` lower) ["hit", "shothit", "sink", "sunk"]
        isMiss = any (`isInfixOf` lower) ["miss", "shotmiss"]
        isSunk = any (`isInfixOf` lower) ["sunk", "shotsunk", "sink"]

    let wnd = appWindow env
    void $ runUI wnd $ do
      -- decide which grid to mark: if the result owner equals our player id, mark our fleet (p1Cells),
      -- otherwise mark target grid (p2Cells)
      mpid <- liftIO $ readIORef (playerIdRef env)
      p1Cells <- liftIO $ readIORef (p1CellsRef env)
      p2Cells <- liftIO $ readIORef (p2CellsRef env)
      sunkMap <- liftIO $ readIORef (sunkPositionsRef env)
      let lookupSunkFor o = maybe [] id (lookup o sunkMap)
      let (cellsToMark, isTarget, valid) = case mpid of
            Just pid -> if owner == pid
                          then (p1Cells, False, x >= 0 && x < length p1Cells && y >= 0 && y < length (head p1Cells))
                          else (p2Cells, True,  x >= 0 && x < length p2Cells && y >= 0 && y < length (head p2Cells))
            Nothing  -> (p2Cells, True,  x >= 0 && x < length p2Cells && y >= 0 && y < length (head p2Cells))

      when valid $ do
        let cell = (cellsToMark !! x) !! y
        -- if server provided explicit sunk positions, mark them all as sunk and remember them
        case mShipPositions of
          Just poses -> do
            -- record sunk positions in client-side map
            liftIO $ do
              lst0 <- readIORef (sunkPositionsRef env)
              let existing = maybe [] id (lookup owner lst0)
                  newList = existing ++ [ p | p <- poses, not (p `elem` existing) ]
                  others = filter ((/= owner) . fst) lst0
              writeIORef (sunkPositionsRef env) ((owner, newList) : others)

            -- mark each sunk pos in the appropriate grid
            forM_ poses $ \(rx,cy) -> do
              let (cellsForPos, isTargetForPos) = case mpid of
                        Just pid -> if owner == pid then (p1Cells, False) else (p2Cells, True)
                        Nothing -> (p2Cells, True)
              when (rx >= 0 && rx < length cellsForPos && cy >= 0 && cy < length (head cellsForPos)) $ do
                let ccell = (cellsForPos !! rx) !! cy
                void $ element ccell # set UI.class_ (if isTargetForPos then "cell target-sunk" else "cell hit")

            -- also record marks for target grid so attacker preserves hits and
            -- upgrades any previous hit/miss at those positions to "sunk"
            liftIO $ do
              lst0 <- readIORef (targetMarksRef env)
              let existing = maybe [] id (lookup owner lst0)
                  -- remove any existing entries at sunk positions, then add them as "sunk"
                  filtered = filter (\(pos, _) -> not (pos `elem` poses)) existing
                  newMarks = filtered ++ map (\p -> (p, "sunk")) poses
                  others = filter ((/= owner) . fst) lst0
              writeIORef (targetMarksRef env) ((owner, newMarks) : others)

          Nothing -> return ()

        when isHit  $ do
          void $ element cell # set UI.class_ (if isTarget then "cell target-hit" else "cell hit")
          -- persist the hit in target marks when this is a target grid (avoid duplicates)
          when isTarget $ liftIO $ do
            lst0 <- readIORef (targetMarksRef env)
            let existing = maybe [] id (lookup owner lst0)
                newEntry = ((x,y), "hit")
                newMarks = if any ((== (x,y)) . fst) existing then existing else existing ++ [newEntry]
                others = filter ((/= owner) . fst) lst0
            writeIORef (targetMarksRef env) ((owner, newMarks) : others)
        when isMiss $ do
          void $ element cell # set UI.class_ (if isTarget then "cell target-miss" else "cell miss")
          when isTarget $ liftIO $ do
            lst0 <- readIORef (targetMarksRef env)
            let existing = maybe [] id (lookup owner lst0)
                newEntry = ((x,y), "miss")
                newMarks = if any ((== (x,y)) . fst) existing then existing else existing ++ [newEntry]
                others = filter ((/= owner) . fst) lst0
            writeIORef (targetMarksRef env) ((owner, newMarks) : others)
        -- if server did not provide explicit sunk positions, fall back to marking this cell
        when (isSunk && mShipPositions == Nothing) $ do
          void $ element cell # set UI.class_ (if isTarget then "cell target-sunk" else "cell target-sunk")
          when isTarget $ liftIO $ do
            lst0 <- readIORef (targetMarksRef env)
            let existing = maybe [] id (lookup owner lst0)
                -- replace any existing entry for this pos with a sunk mark
                filtered = filter ((/= (x,y)) . fst) existing
                newMarks = filtered ++ [((x,y), "sunk")]
                others = filter ((/= owner) . fst) lst0
            writeIORef (targetMarksRef env) ((owner, newMarks) : others)

      -- If a ship was sunk and the server provided its type, add it to the sunk panel
      when isSunk $ case mShipType of
        Just stype -> do
          mpid2 <- liftIO $ readIORef (playerIdRef env)
          let viewer = fromMaybe 1 mpid2
          -- owner is the player whose ship was hit; if owner /= viewer then we've sunk opponent's ship
          when (owner /= viewer) $ do
            sp <- getElementById wnd "sunk-panel"
            case sp of
              Nothing -> return ()
              Just spElem -> do
                let posStr = case mShipPositions of
                               Just poses -> show poses
                               Nothing -> ""
                void $ element spElem #+ [UI.div # set text (stype ++ " " ++ posStr)]
        Nothing -> return ()

      statusDiv <- getElementById wnd "status-msg"
      maybe (return ()) (\st ->
        void $ element st # set text (
          if isHit then " Hit!"
          else if isMiss then " Miss!"
          else if isSunk then " Sunk!"
          else " " ++ r)
        ) statusDiv
      -- Debug: print current persisted target marks and sunk positions
      liftIO $ do
        tm <- readIORef (targetMarksRef env)
        spm <- readIORef (sunkPositionsRef env)
        putStrLn $ "DEBUG: targetMarksRef=" ++ show tm
        putStrLn $ "DEBUG: sunkPositionsRef=" ++ show spm

      -- Re-render boards to ensure persisted marks are applied consistently
      mGV2 <- liftIO $ readIORef (gameViewElem env)
      case mGV2 of
        Nothing -> return ()
        Just gv2 -> do
          p1Cells' <- liftIO $ readIORef (p1CellsRef env)
          p2Cells' <- liftIO $ readIORef (p2CellsRef env)
          gs' <- liftIO $ readIORef (gameStateRef env)
          void $ renderAllBoards env gv2 p1Cells' p2Cells' gs'

  ---------------------------------------------------
  -- 🔄 Board update: server sent our updated board (we are the owner of that board)
  ---------------------------------------------------
  SMUpdateBoard { board = b } -> do
    -- Update the local gameStateRef for our assigned player and re-render
    mpid <- readIORef (playerIdRef env)
    case mpid of
      Nothing -> return ()
      Just pid -> do
        modifyIORef' (gameStateRef env) $ \gs ->
          if pid == 1
            then gs { G.p1 = G.PlayerState b (G.ships (G.p1 gs)) (G.ready (G.p1 gs)) }
            else gs { G.p2 = G.PlayerState b (G.ships (G.p2 gs)) (G.ready (G.p2 gs)) }
        let wnd = appWindow env
        void $ runUI wnd $ do
          mGV <- liftIO $ readIORef (gameViewElem env)
          case mGV of
            Nothing -> return ()
            Just gv -> do
              gs' <- liftIO $ readIORef (gameStateRef env)
              p1Cells <- liftIO $ readIORef (p1CellsRef env)
              p2Cells <- liftIO $ readIORef (p2CellsRef env)
              void $ renderAllBoards env gv p1Cells p2Cells gs'

  ---------------------------------------------------
  -- 🏁 Kết thúc trận
  ---------------------------------------------------
  SMGameOver { winner = w } -> do
    -- Update local game state to GameOver (so client blocks further firing)
    modifyIORef' (gameStateRef env) $ \gs -> G.setWinner gs w
    let wnd = appWindow env
    void $ runUI wnd $ do
      -- re-render boards to reflect final state
      mGV <- liftIO $ readIORef (gameViewElem env)
      case mGV of
        Nothing -> return ()
        Just gv -> do
          gs' <- liftIO $ readIORef (gameStateRef env)
          p1Cells <- liftIO $ readIORef (p1CellsRef env)
          p2Cells <- liftIO $ readIORef (p2CellsRef env)
          void $ renderAllBoards env gv p1Cells p2Cells gs'

      statusDiv <- getElementById wnd "status-msg"
      maybe (return ()) (\st ->
        void $ element st # set text (" Game Over! Winner: Player " ++ show w)
                          # set UI.style [("color", "orange"), ("font-weight", "bold")]
        ) statusDiv

      -- Show the Quit button now that the game is over
      mQuit <- getElementById wnd "quit-btn"
      maybe (return ()) (\qb -> void $ showElement qb) mQuit

  ---------------------------------------------------
  -- Welcome: server assigns player id/name when connecting
  ---------------------------------------------------
  SMWelcome { playerId = pid, playerName = name } -> do
    putStrLn $ "Server: welcome player " ++ show pid ++ " (" ++ name ++ ")"
    writeIORef (playerIdRef env) (Just pid)
    let wnd = appWindow env
    void $ runUI wnd $ do
      statusDiv <- getElementById wnd "status-msg"
      maybe (return ()) (\st -> void $ element st # set text ("Connected as " ++ name ++ " (Player " ++ show pid ++ ")")) statusDiv

      -- After receiving the welcome and storing our player id, re-render
      -- boards so "Your Fleet" correctly shows the viewer's own ships.
      mGV <- liftIO $ readIORef (gameViewElem env)
      case mGV of
        Nothing -> return ()
        Just gv -> do
          gs <- liftIO $ readIORef (gameStateRef env)
          p1Cells <- liftIO $ readIORef (p1CellsRef env)
          p2Cells <- liftIO $ readIORef (p2CellsRef env)
          void $ renderAllBoards env gv p1Cells p2Cells gs

  ---------------------------------------------------
  -- Tin nhắn khác (bỏ qua hoặc debug)
  ---------------------------------------------------
  _ -> return ()


--------------------------------------------------------------------------------
-- Gửi ClientMsg tới server (dùng sockRef trong GameEnv)
--------------------------------------------------------------------------------
sendClientMsg :: GameEnv -> ClientMsg -> IO ()
sendClientMsg env cm = do
    msock <- readIORef (sockRef env)
    case msock of
      Nothing -> putStrLn "Network: not connected, cannot send message"
      Just sock -> NSB.sendAll sock (BL.toStrict (encode cm <> BL.pack "\n"))

--------------------------------------------------------------------------------
-- UI: Login view
--------------------------------------------------------------------------------
createLoginView :: GameEnv -> IORef [[Element]] -> IORef [[Element]] -> UI Element
createLoginView env p1CellsRef p2CellsRef = do
    usernameInput <- UI.input
        # set UI.type_ "text"
        # set (UI.attr "placeholder") "Username"

    passwordInput <- UI.input
        # set UI.type_ "password"
        # set (UI.attr "placeholder") "Password"

    loginBtn <- UI.button # set text "Login"
    signupBtn <- UI.button # set text "Sign up"
    status <- UI.div #. "login-status" # set text "Enter username and password."

    loginDiv <- UI.div #. "login-container" #+
        [ UI.h1 # set text "Battleship Game"
        , UI.div #. "login-form" #+ [element usernameInput, element passwordInput]
        , UI.div #. "login-form" #+ [element loginBtn, element signupBtn]
        , element status
        ]

    let addUserToEnv uid name =
          liftIO $ modifyIORef' (loggedInUsers env) $
              \us -> if any ((== uid) . fst) us then us else us ++ [(uid, name)]

    on UI.click signupBtn $ \_ -> do
        uname <- get value usernameInput
        pwd <- get value passwordInput
        when (not (null uname) && not (null pwd)) $ do
            res <- liftIO $ Users.createUser uname pwd
            case res of
              Left err -> void $ element status # set text ("Signup failed: " ++ err)
              Right u -> do
                la <- liftIO $ Auth.login (Users.userName u) pwd
                case la of
                  Left err -> void $ element status # set text ("Signup succeeded but login failed: " ++ err)
                  Right uid -> do
                    liftIO $ addUserToEnv uid (Users.userName u)
                    void $ element status # set text ("Welcome " ++ Users.userName u)
                    hideElement loginDiv
                    -- Lấy gameView từ env
                    mGameView <- liftIO $ readIORef (gameViewElem env)
                    case mGameView of
                      Just gv -> showElement gv
                      Nothing -> return ()
                    gs <- liftIO $ readIORef (gameStateRef env)
                    p1Cells <- liftIO $ readIORef p1CellsRef
                    p2Cells <- liftIO $ readIORef p2CellsRef
                    mGameView <- liftIO $ readIORef (gameViewElem env)
                    case mGameView of
                      Just gv -> void $ renderAllBoards env gv p1Cells p2Cells gs
                      Nothing -> return ()

    -- Login (note: this code still uses local Auth, not server-auth)
    on UI.click loginBtn $ \_ -> do
        uname <- get value usernameInput
        pwd <- get value passwordInput
        when (not (null uname) && not (null pwd)) $ do
            la <- liftIO $ Auth.login uname pwd
            case la of
              Left err -> void $ element status # set text ("Login failed: " ++ err)
              Right uid -> do
                mu <- liftIO $ Users.findUserById uid
                let name = maybe uname Users.userName mu
                liftIO $ addUserToEnv uid name
                void $ element status # set text ("Welcome " ++ name)
                hideElement loginDiv
                -- Lấy gameView từ env
                mGameView <- liftIO $ readIORef (gameViewElem env)
                case mGameView of
                  Just gv -> showElement gv
                  Nothing -> return ()
                liftIO $ do
                    msock <- readIORef (sockRef env)
                    case msock of
                      Nothing -> do
                        -- spawn background connection and ignore ThreadId
                        void $ forkIO $ tryConnectAndListen env "127.0.0.1" "3000"
                        return ()
                      Just _ -> return ()  -- đã có kết nối, không cần tạo lại

                gs <- liftIO $ readIORef (gameStateRef env)
                p1Cells <- liftIO $ readIORef p1CellsRef
                p2Cells <- liftIO $ readIORef p2CellsRef
                mGameView <- liftIO $ readIORef (gameViewElem env)
                case mGameView of
                  Just gv -> void $ renderAllBoards env gv p1Cells p2Cells gs
                  Nothing -> return ()

    return loginDiv

--------------------------------------------------------------------------------
-- UI: Game view (giữ logic cũ, nhưng gọi sendClientMsg khi cần)
--------------------------------------------------------------------------------
createGameView :: GameEnv -> IORef [[Element]] -> IORef [[Element]] -> UI Element
createGameView env p1CellsRef p2CellsRef = do
  (myBoardElem, myBoardCells) <- createBoard "my-board" "Your Fleet"
  (targetBoardElem, targetBoardCells) <- createBoard "target-board" "Target Grid"

  liftIO $ writeIORef p1CellsRef myBoardCells
  liftIO $ writeIORef p2CellsRef targetBoardCells

  carrierBtn    <- UI.button #. "ship-btn carrier"    # set text "Carrier (5)"
  battleshipBtn <- UI.button #. "ship-btn battleship" # set text "Battleship (4)"
  cruiserBtn    <- UI.button #. "ship-btn cruiser"    # set text "Cruiser (3)"
  submarineBtn  <- UI.button #. "ship-btn submarine"  # set text "Submarine (3)"
  destroyerBtn  <- UI.button #. "ship-btn destroyer"  # set text "Destroyer (2)"

  shipSelection <- UI.div #. "ship-selection" #+ map element
    [ carrierBtn, battleshipBtn, cruiserBtn, submarineBtn, destroyerBtn ]

  rotateBtn <- UI.button #. "control-btn" # set text "Rotate (Space)"
  readyBtn  <- UI.button #. "control-btn" # set text "Ready"
  quitBtn   <- UI.button #. "control-btn quit" # set UI.id_ "quit-btn" # set text "Quit"

  -- give the status div an id so external threads (network listener) can find it via getElementById
  statusMsg <- UI.div # set UI.id_ "status-msg" #. "status-msg" # set text "Select a ship to place"

  -- panel to show which enemy ships we've sunk
  sunkPanel <- UI.div # set UI.id_ "sunk-panel" #. "sunk-panel" # set text ""

  -- hide Quit initially; it will be shown when the game is over
  void $ hideElement quitBtn
  
  -- Create quit dialog with Restart and Logout options
  quitDialog <- UI.div # set UI.id_ "quit-dialog" #. "quit-dialog" # set style [("display", "none")] #+
    [ UI.div #. "quit-dialog-content" #+ [
        UI.h3 # set text "What would you like to do?"
      , UI.button # set UI.id_ "restart-btn" # set text "Restart (New Game)"
      , UI.button # set UI.id_ "logout-btn" # set text "Logout"
      , UI.button # set UI.id_ "cancel-btn" # set text "Cancel"
      ]
    ]
  
  controlPanel <- UI.div #. "control-panel" #+
    [ element shipSelection
    , element rotateBtn
    , element readyBtn
    , element quitBtn
    , element statusMsg
    , UI.h3 # set text "Sunk ships:"
    , element sunkPanel
    , element quitDialog
    ]

  boardsElem <- UI.div #. "boards" #+
    [ UI.div #. "board-container" #+ [ UI.h2 # set text "Your Fleet", element myBoardElem ]
    , UI.div #. "board-container" #+ [ UI.h2 # set text "Target Grid", element targetBoardElem ]
    ]

  gameDiv <- UI.div #. "game-container" #+ [ element boardsElem, element controlPanel ]

  setupGameEvents env gameDiv rotateBtn readyBtn quitBtn statusMsg
    carrierBtn battleshipBtn cruiserBtn submarineBtn destroyerBtn
    myBoardCells targetBoardCells p1CellsRef p2CellsRef quitDialog

  return gameDiv

--------------------------------------------------------------------------------
-- Tạo board DOM
--------------------------------------------------------------------------------
createBoard :: String -> String -> UI (Element, [[Element]])
createBoard boardId title = do
    rowsAndCells <- forM [0..9] $ \r -> do
        cells <- forM [0..9] $ \c -> do
            cell <- UI.td #. "cell" # set UI.id_ (boardId ++ "-" ++ show r ++ "-" ++ show c)
            return cell
        rowElem <- UI.tr #+ map element cells
        return (rowElem, cells)
    let rows = map fst rowsAndCells
        cellsMatrix = map snd rowsAndCells
    table <- UI.table #. "game-board" # set UI.id_ boardId #+ map element rows
    container <- UI.div #. "board-container" #+
        [ UI.h2 # set text title
        , element table
        ]
    return (container, cellsMatrix)

--------------------------------------------------------------------------------
-- setupGameEvents: xử lý click/placing/ready/fire — gửi message cho server
--------------------------------------------------------------------------------
setupGameEvents :: GameEnv -> Element ->
                   Element -> Element -> Element -> Element ->
                   Element -> Element -> Element -> Element -> Element ->
                   [[Element]] -> [[Element]] ->
                   IORef [[Element]] -> IORef [[Element]] -> Element -> UI ()
setupGameEvents env gameDiv rotateBtn readyBtn quitBtn statusMsg
                carrierBtn battleshipBtn cruiserBtn submarineBtn destroyerBtn
                myBoardCells targetBoardCells p1CellsRef p2CellsRef quitDialog = do

    currentShipTypeRef <- liftIO $ newIORef T.Carrier
    shipsPlacedRef     <- liftIO $ newIORef ([] :: [S.Ship])
    isHorizontalRef    <- liftIO $ newIORef True
    isPlacingRef       <- liftIO $ newIORef True

    -- Delay để tìm các button trong dialog (chúng được thêm vào DOM sau)
    restartBtnRef <- liftIO $ newIORef (Nothing :: Maybe Element)
    logoutBtnRef <- liftIO $ newIORef (Nothing :: Maybe Element)
    cancelBtnRef <- liftIO $ newIORef (Nothing :: Maybe Element)

    let setStatus txt = void $ element statusMsg # set text txt
    setStatus "Choose a ship to place, then click on your board."

    let mkShipBtn btn shipType = on UI.click btn $ \_ -> do
            liftIO $ writeIORef currentShipTypeRef shipType
            setStatus $ "Selected " ++ show shipType ++ ". Click on your board to place it."
    mkShipBtn carrierBtn T.Carrier
    mkShipBtn battleshipBtn T.Battleship
    mkShipBtn cruiserBtn T.Cruiser
    mkShipBtn submarineBtn T.Submarine
    mkShipBtn destroyerBtn T.Destroyer

    on UI.click rotateBtn $ \_ -> do
        liftIO $ modifyIORef' isHorizontalRef not
        isH <- liftIO $ readIORef isHorizontalRef
        setStatus $ "Orientation: " ++ (if isH then "Horizontal" else "Vertical")

    -- placing on my board: gửi CMPlaceShip lên server (nếu kết nối),
    -- nếu không có server, vẫn dùng placeShipForPlayer local
    forM_ [(r,c) | r <- [0..9], c <- [0..9]] $ \(r,c) -> do
        let cell = myBoardCells !! r !! c
        on UI.click cell $ \_ -> do
            isPlacing <- liftIO $ readIORef isPlacingRef
            when isPlacing $ do
              currentShipType <- liftIO $ readIORef currentShipTypeRef
              isH <- liftIO $ readIORef isHorizontalRef
              placed <- liftIO $ readIORef shipsPlacedRef

              -- 1) Nếu đã đặt đủ 5 tàu thì chặn luôn
              if length placed >= 5
                then setStatus "Bạn đã đặt đủ 5 tàu."
                else do
                  case S.placeShipPositions (r,c) isH currentShipType of
                    Nothing -> setStatus "Cannot place ship here (out of bounds)."
                    Just positions -> do
                      let overlaps = any (\s -> any (`elem` S.positions s) positions) placed
                      if overlaps
                        then setStatus "Cannot place ship here (overlap)."
                        else do
                          let sid = length placed + 1
                              newShip = S.Ship sid currentShipType positions
                              newPlaced = newShip : placed

                          msock <- liftIO $ readIORef (sockRef env)
                          case msock of
                            -- ONLINE: gửi yêu cầu lên server. Prefer optimistic local update
                            -- only if server already assigned us a player id; otherwise
                            -- wait for server confirmation (SMUpdateBoard) to avoid placing
                            -- on the wrong board (was causing player 2 to show player 1's ships).
                            Just _ -> do
                              liftIO $ sendClientMsg env (CMPlaceShip sid (show currentShipType) (r,c) isH)
                              mpid <- liftIO $ readIORef (playerIdRef env)
                              case mpid of
                                Nothing -> do
                                  -- No assigned id yet; do not optimistic-local update.
                                  setStatus $ "Placed (request sent) " ++ show currentShipType ++ " at " ++ show (r,c) ++ ", awaiting server confirmation..."
                                Just vid -> do
                                  -- optimistic local update so UI thấy result immediately
                                  gs <- liftIO $ readIORef (gameStateRef env)
                                  case G.placeShipForPlayer gs vid newShip of
                                    Nothing -> setStatus "Local placement failed (conflict)."
                                    Just gs' -> do
                                      liftIO $ modifyIORef' shipsPlacedRef (const newPlaced)
                                      liftIO $ writeIORef (gameStateRef env) gs'
                                      void $ renderAllBoards env gameDiv myBoardCells targetBoardCells gs'
                                      setStatus $ "Placed (request sent) " ++ show currentShipType ++ " at " ++ show (r,c)
                                      -- nếu đã đủ 5, chặn tiếp
                                      when (length newPlaced >= 5) $ do
                                        liftIO $ writeIORef isPlacingRef False
                                        setStatus "All ships placed — press Ready to start the game."

                            -- OFFLINE: làm như cục bộ trước (như trước)
                            Nothing -> do
                              gs <- liftIO $ readIORef (gameStateRef env)
                              -- offline viewer id defaults to Player 1
                              mpid <- liftIO $ readIORef (playerIdRef env)
                              let vid = fromMaybe 1 mpid
                              case G.placeShipForPlayer gs vid newShip of
                                Nothing -> setStatus "Failed to place ship into local game state (conflict)."
                                Just gs' -> do
                                  liftIO $ writeIORef shipsPlacedRef newPlaced
                                  liftIO $ writeIORef (gameStateRef env) gs'
                                  void $ renderAllBoards env gameDiv myBoardCells targetBoardCells gs'
                                  setStatus $ "Placed " ++ show currentShipType
                                  when (length newPlaced >= 5) $ do
                                    liftIO $ writeIORef isPlacingRef False
                                    setStatus "All ships placed — press Ready to start the game."


    -- Ready: chỉ mark local ready or gửi CMReady nếu có server
    on UI.click readyBtn $ \_ -> do
        placed <- liftIO $ readIORef shipsPlacedRef
        if length placed < 5
          then setStatus "You must place all your ships before starting (5 ships)."
          else do
            msock <- liftIO $ readIORef (sockRef env)
            case msock of
              Just _ -> do
                liftIO $ sendClientMsg env CMReady
                setStatus "Ready sent to server. Waiting..."
              Nothing -> do
                -- local: mark viewer ready (use assigned player id or default to 1)
                gs0 <- liftIO $ readIORef (gameStateRef env)
                mpid <- liftIO $ readIORef (playerIdRef env)
                let vid = fromMaybe 1 mpid
                    gsReady = G.setPlayerReady gs0 vid
                liftIO $ writeIORef (gameStateRef env) gsReady
                liftIO $ writeIORef isPlacingRef False
                setStatus "You are ready (local). Waiting for opponent..."
                void $ renderAllBoards env gameDiv myBoardCells targetBoardCells gsReady

    -- Quit button: show dialog with Restart and Logout options
    on UI.click quitBtn $ \_ -> do
        void $ showElement quitDialog
        -- Find the dialog buttons on first click
        mRestartBtn <- liftIO $ readIORef restartBtnRef
        mLogoutBtn <- liftIO $ readIORef logoutBtnRef
        mCancelBtn <- liftIO $ readIORef cancelBtnRef
        when (isNothing mRestartBtn) $ do
          rBtn <- getElementById (appWindow env) "restart-btn"
          liftIO $ writeIORef restartBtnRef rBtn
        when (isNothing mLogoutBtn) $ do
          lBtn <- getElementById (appWindow env) "logout-btn"
          liftIO $ writeIORef logoutBtnRef lBtn
        when (isNothing mCancelBtn) $ do
          cBtn <- getElementById (appWindow env) "cancel-btn"
          liftIO $ writeIORef cancelBtnRef cBtn

    -- Restart button: xóa hết dữ liệu trận cũ và quay lại đặt tàu
    liftIO $ do
      threadDelay 100000  -- 0.1 second delay
      mRestartBtn <- readIORef restartBtnRef
      case mRestartBtn of
        Just restartBtn -> do
          void $ runUI (appWindow env) $ on UI.click restartBtn $ \_ -> do
            -- Gửi CMQuit nếu có server
            msock <- liftIO $ readIORef (sockRef env)
            case msock of
              Just _ -> liftIO $ sendClientMsg env CMQuit
              Nothing -> return ()
            
            -- Xóa hết dữ liệu trận cũ
            liftIO $ writeIORef (targetMarksRef env) []
            liftIO $ writeIORef (sunkPositionsRef env) []
            liftIO $ writeIORef (gameStateRef env) G.initState
            liftIO $ writeIORef shipsPlacedRef []
            liftIO $ writeIORef isPlacingRef True
            liftIO $ writeIORef currentShipTypeRef T.Carrier
            liftIO $ writeIORef isHorizontalRef True
            
            -- Reset status message và tất cả UI elements
            setStatus "Restarting... Choose a ship to place, then click on your board."
            
            -- Xóa tất cả đánh dấu trên các board
            myCells <- liftIO $ readIORef p1CellsRef
            tgtCells <- liftIO $ readIORef p2CellsRef
            forM_ (concat myCells) $ \cell -> void $ element cell # set UI.class_ "cell"
            forM_ (concat tgtCells) $ \cell -> void $ element cell # set UI.class_ "cell"
            
            -- Render lại boards với dữ liệu trống
            gs <- liftIO $ readIORef (gameStateRef env)
            void $ renderAllBoards env gameDiv myCells tgtCells gs
            
            -- Ẩn dialog và quit button
            void $ hideElement quitDialog
            void $ hideElement quitBtn
        Nothing -> return ()
    
    -- Logout button: quay lại login, giữ dữ liệu tàu
    liftIO $ do
      mLogoutBtn <- readIORef logoutBtnRef
      case mLogoutBtn of
        Just logoutBtn -> do
          void $ runUI (appWindow env) $ on UI.click logoutBtn $ \_ -> do
            -- Gửi CMQuit nếu có server
            msock <- liftIO $ readIORef (sockRef env)
            case msock of
              Just _ -> liftIO $ sendClientMsg env CMQuit
              Nothing -> return ()
            
            -- Xóa chỉ dữ liệu ván chơi hiện tại (target grid, sunk ships)
            -- Giữ lại dữ liệu đặt tàu (shipsPlacedRef, gameStateRef với các tàu được đặt)
            liftIO $ writeIORef (targetMarksRef env) []
            liftIO $ writeIORef (sunkPositionsRef env) []
            liftIO $ writeIORef (playerIdRef env) Nothing
            
            -- Reset phase về PlacingShips để có thể đặt tàu lại
            liftIO $ modifyIORef' (gameStateRef env) $ \gs -> gs { G.phase = G.PlacingShips }
            
            -- Xóa kết nối socket
            liftIO $ writeIORef (sockRef env) Nothing
            
            -- Xóa tất cả đánh dấu trên target grid (giữ lại my fleet)
            tgtCells <- liftIO $ readIORef p2CellsRef
            forM_ (concat tgtCells) $ \cell -> void $ element cell # set UI.class_ "cell"
            
            -- Ẩn dialog, quit button và game view
            void $ hideElement quitDialog
            void $ hideElement quitBtn
            void $ hideElement gameDiv
            
            -- Lấy login view từ env và hiển thị
            mLoginView <- liftIO $ readIORef (loginViewElem env)
            case mLoginView of
              Just lv -> void $ showElement lv
              Nothing -> return ()
        Nothing -> return ()

    -- Cancel button: đóng dialog
    liftIO $ do
      mCancelBtn <- readIORef cancelBtnRef
      case mCancelBtn of
        Just cancelBtn -> do
          void $ runUI (appWindow env) $ on UI.click cancelBtn $ \_ -> do
            void $ hideElement quitDialog
        Nothing -> return ()

    -- Firing (target board): gửi CMFire nếu có server; nếu offline thì local applyFire
    -- Firing (target board): gửi CMFire nếu có server; nếu offline thì local applyFire
    forM_ [(r,c) | r <- [0..9], c <- [0..9]] $ \(r,c) -> do
        let tcell = targetBoardCells !! r !! c
        on UI.click tcell $ \_ -> do
            gs <- liftIO $ readIORef (gameStateRef env)
            when (G.phase gs == G.Playing) $ do
                msock <- liftIO $ readIORef (sockRef env)
                case msock of
                  Just _ -> do
                    liftIO $ sendClientMsg env (CMFire (r,c))
                    -- đánh dấu trên target grid (optimistic)
                    void $ element tcell # set UI.class_ "cell target-fired"
                    setStatus $ "Fired at " ++ show (r,c) ++ ", waiting for result..."
                  Nothing -> do
                    -- local apply
                    let attacker = G.turn gs
                        (gs', res) = G.applyFire gs attacker (r,c)
                    liftIO $ writeIORef (gameStateRef env) gs'
                    let msg = case res of
                              L.ShotMiss -> "Miss"
                              L.ShotHit  -> "Hit"
                              L.ShotSunk _ -> "Sunk!"
                    case res of
                      L.ShotMiss -> void $ element tcell # set UI.class_ "cell target-miss"
                      _          -> void $ element tcell # set UI.class_ "cell target-hit"
                    setStatus $ "Fired at " ++ show (r,c) ++ ": " ++ msg
                    void $ renderAllBoards env gameDiv myBoardCells targetBoardCells gs'


    return ()

--------------------------------------------------------------------------------
-- Render helpers (giữ nguyên logic của bạn)
--------------------------------------------------------------------------------
renderAllBoards :: GameEnv -> Element -> [[Element]] -> [[Element]] -> G.GameState -> UI ()
renderAllBoards env _ myCells targetCells gs = do
    -- If the server hasn't yet assigned a player id (SMWelcome), avoid
    -- assuming the viewer is Player 1. In that case render both boards
    -- as empty placeholders. Once SMWelcome arrives the handler will
    -- re-render with the correct viewer id.
    mpid <- liftIO $ readIORef (playerIdRef env)
    case mpid of
      Nothing -> do
        -- clear both grids so no ships are shown until we know our id
        let clearCells elems = forM_ (concat elems) $ \cell -> void $ element cell # set UI.class_ "cell"
        clearCells myCells
        clearCells targetCells
      Just viewer -> do
        let opponent = if viewer == 1 then 2 else 1
        void $ renderBoardElems env myCells gs viewer
        void $ renderBoardElems env targetCells gs opponent

renderBoardElems :: GameEnv -> [[Element]] -> G.GameState -> Int -> UI ()
renderBoardElems env elems gs owner = do
    let b = G.getPlayerBoard gs owner
    mpid <- liftIO $ readIORef (playerIdRef env)
    sunkMap <- liftIO $ readIORef (sunkPositionsRef env)
    let viewer = fromMaybe 1 mpid  -- default to Player 1 if not assigned
        isMyFleet = owner == viewer  -- this is my fleet board
        isTargetGrid = owner /= viewer  -- this is opponent's board (my target)
        ownerSunkPositions = maybe [] id (lookup owner sunkMap)

    -- Debug: show persisted marks when rendering (helps trace disappearing marks)
    liftIO $ do
      tm <- readIORef (targetMarksRef env)
      let ownerTargetsCount = length (maybe [] id (lookup owner tm))
      putStrLn $ "DEBUG renderBoardElems: owner=" ++ show owner ++ ", viewer=" ++ show viewer ++ ", ownerTargetsCount=" ++ show ownerTargetsCount ++ ", ownerSunkCount=" ++ show (length ownerSunkPositions)

    forM_ (zip [0..] elems) $ \(r,row) ->
      forM_ (zip [0..] row) $ \(c,cell) -> do
      let mcell = B.getCell b (r,c)
      -- Check persisted target marks first (so attacker preserves marks even if board lacks info)
      tm <- liftIO $ readIORef (targetMarksRef env)
      let ownerTargets = maybe [] id (lookup owner tm)
      case lookup (r,c) ownerTargets of
        Just markType -> case markType of
          "sunk" -> if isTargetGrid then void $ element cell # set UI.class_ "cell target-sunk" else void $ element cell # set UI.class_ "cell hit"
          "hit"  -> if isTargetGrid then void $ element cell # set UI.class_ "cell target-hit" else void $ element cell # set UI.class_ "cell hit"
          "miss" -> if isTargetGrid then void $ element cell # set UI.class_ "cell target-miss" else void $ element cell # set UI.class_ "cell miss"
          _      -> void $ element cell # set UI.class_ "cell"
        Nothing -> do
          -- If this position is known to be part of a sunk ship for this owner, mark as sunk
          if (r,c) `elem` ownerSunkPositions
            then if isTargetGrid
                   then void $ element cell # set UI.class_ "cell target-sunk"
                   else void $ element cell # set UI.class_ "cell hit"
            else case mcell of
              Just T.Empty -> void $ element cell # set UI.class_ "cell"
              Just (T.ShipPart _) -> if isMyFleet then void $ element cell # set UI.class_ "cell ship" else void $ element cell # set UI.class_ "cell"
              Just T.Hit -> if isMyFleet then void $ element cell # set UI.class_ "cell hit" else void $ element cell # set UI.class_ "cell target-hit"
              Just T.Miss -> if isMyFleet then void $ element cell # set UI.class_ "cell miss" else void $ element cell # set UI.class_ "cell target-miss"
              _ -> void $ element cell # set UI.class_ "cell"


--------------------------------------------------------------------------------
-- Random ships (unchanged)
--------------------------------------------------------------------------------
generateRandomShips :: IO [S.Ship]
generateRandomShips = do
    let types = [T.Carrier, T.Battleship, T.Cruiser, T.Submarine, T.Destroyer]
    let go _ [] acc = return (reverse acc)
        go occ (st:sts) acc = do
            let tryPlace = do
                  r <- randomRIO (0,9)
                  c <- randomRIO (0,9)
                  h <- randomRIO (False,True)
                  case S.placeShipPositions (r,c) h st of
                    Nothing -> tryPlace
                    Just poss -> if any (`elem` occ) poss then tryPlace else return (poss,h)
            (poss,_) <- tryPlace
            let sid = length acc + 1
                ship = S.Ship sid st poss
            go (occ ++ poss) sts (ship:acc)
    go [] types []

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
hideElement, showElement :: Element -> UI ()
hideElement e = void $ element e # set style [("display", "none")]
showElement e = void $ element e # set style [("display", "block")]
