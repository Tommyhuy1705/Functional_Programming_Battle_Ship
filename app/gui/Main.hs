{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE ScopedTypeVariables #-}


module Main where
import Data.Char (toLower)
import Data.List (isInfixOf)

import qualified Database.Users as Users
import qualified Database.Auth as Auth

import Control.Exception (try, SomeException)

-- Thư viện GUI chính
import qualified Graphics.UI.Threepenny as UI
import Graphics.UI.Threepenny.Core
import System.Environment (getArgs)

-- Thư viện Mạng (TCP Sockets)
import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB
import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forever, unless, void, when, forM_, forM)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson (encode, decode)

-- Các module Game 
import qualified Game.State as G
import qualified Game.Board as B
import qualified Game.Types as T
import qualified Game.Ship as S
import qualified Game.Logic as L

-- Tiện ích khác
import Network.Message
import Data.IORef
import System.Random (randomRIO)
import Data.Maybe (fromMaybe, listToMaybe, isNothing)
import Data.Foldable (traverse_)


-- Môi trường chạy GUI
data GameEnv = GameEnv
  { appWindow     :: Window                                 -- Cửa sổ trình duyệt
  , gameStateRef  :: IORef G.GameState                      -- Trạng thái game được chia sẻ
  , loggedInUsers :: IORef [(Int, String)]
  , sockRef       :: IORef (Maybe NS.Socket)                -- Socket kết nối server
  , p1CellsRef    :: IORef [[Element]]                      -- Ma trận ô của bảng người chơi 1
  , p2CellsRef    :: IORef [[Element]]                      -- Ma trận ô của bảng người chơi 2
  , gameViewElem  :: IORef (Maybe Element)                  -- Tham chiếu view game chính
  , playerIdRef   :: IORef (Maybe Int)                      -- ID được server cấp
  , sunkPositionsRef :: IORef [(Int, [T.Pos])]              -- Vị trí tàu đã chìm để render
  , targetMarksRef :: IORef [(Int, [((Int,Int), String)])]  -- Ghi lại 'hit'/'miss' trên target grid
  , loginViewElem :: IORef (Maybe Element)                  -- Tham chiếu view Login
  , shipsPlacedRef     :: IORef [S.Ship]                    -- Tàu đã đặt
  , isPlacingRef       :: IORef Bool                        -- Đang ở chế độ đặt tàu?
  , currentShipTypeRef :: IORef T.ShipType                  -- Loại tàu đang chọn
  , isHorizontalRef    :: IORef Bool                        -- Hướng đặt: True = ngang
  , rematchBtn         :: Element                           -- Nút Rematch
  }

-- Lấy IP Radmin VPN
getRadminIP :: IO String
getRadminIP = do
    eres <- try $ NS.withSocketsDo $ do
        addrInfos <- NS.getAddrInfo Nothing (Just "26.17.201.201") Nothing
        let addr = head addrInfos
        return (NS.addrAddress addr)
    case eres of
        Left (_ :: SomeException) -> return "127.0.0.1"
        Right _ -> return "26.17.201.201"

-- Entry point chính của ứng dụng GUI
main :: IO ()
main = do
    putStrLn "Starting Battleship GUI..."
    putStrLn "Serving static from: app/gui/static"

    args <- getArgs
    let allowRemote = "--allow-remote-access" `elem` args

    -- Lấy IP
    ip <- getRadminIP

    putStrLn ""
    putStrLn "======================================================"
    putStrLn "Battleship GUI is running!"
    if allowRemote then do
        putStrLn "Share this link with your friend on Radmin VPN:"
        putStrLn $ "http://" ++ ip ++ ":8023"
      else do
        putStrLn "Access locally at:"
        putStrLn "http://127.0.0.1:8023"
    putStrLn "======================================================"
    putStrLn ""

    -- Cấu hình Threepenny
    let config = defaultConfig
            { jsPort   = Just 8023
            , jsStatic = Just "app/gui/static"
            , jsAddr   = if allowRemote then Just "0.0.0.0" else Nothing
            }

    -- Khởi động GUI
    startGUI config setup

setup :: Window -> UI ()
setup window = do
  void $ return window # set UI.title "Battleship (Threepenny GUI)"
  void $ UI.addStyleSheet window "style.css"

  -- State
  gsRef <- liftIO $ newIORef G.initState
  usersRef <- liftIO $ newIORef []
  sockR <- liftIO $ newIORef Nothing
  p1CellsRef <- liftIO $ newIORef []
  p2CellsRef <- liftIO $ newIORef []
  gameViewElem <- liftIO $ newIORef Nothing
  playerIdRef <- liftIO $ newIORef Nothing
  sunkPositionsRef <- liftIO $ newIORef []
  targetMarksRef <- liftIO $ newIORef []
  loginViewElem <- liftIO $ newIORef Nothing

  shipsPlacedRef <- liftIO $ newIORef []
  isPlacingRef <- liftIO $ newIORef True
  currentShipTypeRef <- liftIO $ newIORef T.Carrier
  isHorizontalRef <- liftIO $ newIORef True

  -- Rematch Button
  rematchBtn <- UI.button #+ [string "Rematch"]
  void $ element rematchBtn # set style [("display", "none")]

  -- Environment
  let env = GameEnv
        { appWindow          = window
        , gameStateRef       = gsRef
        , loggedInUsers      = usersRef
        , sockRef            = sockR
        , p1CellsRef         = p1CellsRef
        , p2CellsRef         = p2CellsRef
        , gameViewElem       = gameViewElem
        , playerIdRef        = playerIdRef
        , sunkPositionsRef   = sunkPositionsRef
        , targetMarksRef     = targetMarksRef
        , loginViewElem      = loginViewElem
        , shipsPlacedRef     = shipsPlacedRef
        , isPlacingRef       = isPlacingRef
        , currentShipTypeRef = currentShipTypeRef
        , isHorizontalRef    = isHorizontalRef
        , rematchBtn         = rematchBtn
        }

  -- Tạo UI views
  loginView <- createLoginView env p1CellsRef p2CellsRef
  liftIO $ writeIORef loginViewElem (Just loginView)
  gameView <- createGameView env p1CellsRef p2CellsRef
  liftIO $ writeIORef gameViewElem (Just gameView)
  hideElement gameView

  -- Attach tất cả vào body
  void $ getBody window #+ [element loginView, element gameView, element rematchBtn]

  return ()

-- Kết nối
tryConnectAndListen :: GameEnv -> String -> String -> IO ()
tryConnectAndListen env host port = NS.withSocketsDo $ do
    eres <- tryConnect host port
    case eres of
      Left err -> putStrLn $ "Network: failed to connect: " ++ err
      Right sock -> do
          putStrLn "Network: connected to server"
          writeIORef (sockRef env) (Just sock)

          -- Bắt đầu vòng lặp lắng nghe từ server
          forever $ do
            bs <- NSB.recv sock 4096
            putStrLn $ "Network: received raw: " ++ show bs
            if BS.null bs
              then do
                -- Nếu server đóng kết nối, thoát vòng lặp
                putStrLn "Network: server closed connection."
                writeIORef (sockRef env) Nothing
                putStrLn "Listener thread exiting."
                return ()
              else do
                let parts = filter (not . BS.null) $ BS.split 10 bs
                forM_ parts $ \part -> case decode (BL.fromStrict part) :: Maybe ServerMsg of
                  Nothing -> putStrLn $ "Network: invalid server message: " ++ show part
                  Just sm -> handleServerMsgIO env sm

-- Thử kết nối TCP, trả về Lỗi hoặc Socket
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

-- Xử lý ServerMsg
-- Cập nhật gameStateRef và yêu cầu UI re-render
handleServerMsgIO :: GameEnv -> ServerMsg -> IO ()
handleServerMsgIO env msg = case msg of

  -- [Game Phase] Server thay đổi giai đoạn game
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

          -- Cập nhật dòng trạng thái trên UI
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

  -- [Your Turn] Server thông báo đến lượt của client này
  SMYourTurn -> do
    let wnd = appWindow env
    void $ runUI wnd $ do
      statusDiv <- getElementById wnd "status-msg"
      maybe (return ()) (\st ->
        void $ element st # set text " Your turn!"
                          # set UI.style [("color", "lime"), ("font-weight", "bold")]
        ) statusDiv
  
  -- [Opponent Turn] Server thông báo đến lượt của đối thủ
  SMOpponentTurn -> do
    let wnd = appWindow env
    void $ runUI wnd $ do
      statusDiv <- getElementById wnd "status-msg"
      maybe (return ()) (\st ->
        void $ element st # set text " Opponent’s turn..."
                          # set UI.style [("color", "gray"), ("font-weight", "normal")]
        ) statusDiv

  -- [Fire Result]
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
        -- Nếu tàu bị chìm, server sẽ trả về toàn bộ vị trí của tàu đó
        case mShipPositions of
          Just poses -> do
            -- Lưu lại các vị trí chìm để render cho đúng (màu đỏ sẫm)
            liftIO $ do
              lst0 <- readIORef (sunkPositionsRef env)
              let existing = maybe [] id (lookup owner lst0)
                  newList = existing ++ [ p | p <- poses, not (p `elem` existing) ]
                  others = filter ((/= owner) . fst) lst0
              writeIORef (sunkPositionsRef env) ((owner, newList) : others)

            -- Đánh dấu tất cả các ô chìm trên UI
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

          Nothing -> return () -- Nếu không phải chìm, chỉ là Hit hoặc Miss

        -- Chỉ là 'Hit'
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
        
        -- Chỉ là 'Miss'
        when isMiss $ do
          void $ element cell # set UI.class_ (if isTarget then "cell target-miss" else "cell miss")
          when isTarget $ liftIO $ do
            lst0 <- readIORef (targetMarksRef env)
            let existing = maybe [] id (lookup owner lst0)
                newEntry = ((x,y), "miss")
                newMarks = if any ((== (x,y)) . fst) existing then existing else existing ++ [newEntry]
                others = filter ((/= owner) . fst) lst0
            writeIORef (targetMarksRef env) ((owner, newMarks) : others)
        
        when (isSunk && mShipPositions == Nothing) $ do
          void $ element cell # set UI.class_ (if isTarget then "cell target-sunk" else "cell target-sunk")
          when isTarget $ liftIO $ do
            lst0 <- readIORef (targetMarksRef env)
            let existing = maybe [] id (lookup owner lst0)
                filtered = filter ((/= (x,y)) . fst) existing
                newMarks = filtered ++ [((x,y), "sunk")]
                others = filter ((/= owner) . fst) lst0
            writeIORef (targetMarksRef env) ((owner, newMarks) : others)

      -- Hiện panel thông báo tàu đã chìm
      when isSunk $ case mShipType of
        Just stype -> do
          mpid2 <- liftIO $ readIORef (playerIdRef env)
          let viewer = fromMaybe 1 mpid2
          -- Chỉ hiển thị panel chìm nếu người xem không phải là chủ tàu
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
  
  -- [SỰ KIỆN] Đối thủ yêu cầu chơi lại
  SMRematchRequested { fromPlayer = pid } -> do
    putStrLn $ "Opponent Player " ++ show pid ++ " requested a rematch."
    let wnd = appWindow env
    void $ runUI wnd $ showRematchDialog env pid
  
  -- [SỰ KIỆN] Cả hai đã đồng ý chơi lại
  SMRematchAccepted -> do
      putStrLn "Rematch accepted by both players."
      let wnd = appWindow env
      void $ runUI wnd $ do
        statusDiv <- getElementById wnd "status-msg"
        maybe (return ()) (\st -> do
          liftIO $ resetLocalPlacement env st  -- 👈 gọi reset ở đây
          void $ element st # set text "Rematch accepted — place your ships!"
                            # set UI.style [("color", "lime"), ("font-weight", "bold")]
          ) statusDiv


  SMRematchDeclined -> do
    putStrLn "Opponent declined rematch."
    let wnd = appWindow env
    void $ runUI wnd $ do
      statusDiv <- getElementById wnd "status-msg"
      maybe (return ()) (\st -> liftIO $ resetLocalPlacement env st) statusDiv

  -- Server gửi bản cập nhật bàn cờ
  SMUpdateBoard { board = b } -> do
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

  -- Trò chơi kết thúc
  SMGameOver { winner = w } -> do
    modifyIORef' (gameStateRef env) $ \gs -> G.setWinner gs w
    let wnd = appWindow env
    void $ runUI wnd $ do
      -- Render lại lần cuối
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

      -- Hiển thị nút "Quit"
      mQuit <- getElementById wnd "quit-btn"
      maybe (return ()) (\qb -> void $ showElement qb) mQuit

  -- Client kết nối thành công, server cấp ID
  SMWelcome { playerId = pid, playerName = name } -> do
    putStrLn $ "Server: welcome player " ++ show pid ++ " (" ++ name ++ ")"
    writeIORef (playerIdRef env) (Just pid)
    let wnd = appWindow env
    void $ runUI wnd $ do
      statusDiv <- getElementById wnd "status-msg"
      maybe (return ()) (\st -> void $ element st # set text ("Connected as " ++ name ++ " (Player " ++ show pid ++ ")")) statusDiv

      -- Render lại bàn cờ để gán đúng "Your Fleet"
      mGV <- liftIO $ readIORef (gameViewElem env)
      case mGV of
        Nothing -> return ()
        Just gv -> do
          gs <- liftIO $ readIORef (gameStateRef env)
          p1Cells <- liftIO $ readIORef (p1CellsRef env)
          p2Cells <- liftIO $ readIORef (p2CellsRef env)
          void $ renderAllBoards env gv p1Cells p2Cells gs
  _ -> return ()

-- Hiện hộp thoại hỏi rematch
showRematchDialog :: GameEnv -> Int -> UI ()
showRematchDialog env fromPid = do
  dlg <- UI.div #. "dialog" #+ [string $ "Player " ++ show fromPid ++ " wants a rematch!"]
  yesBtn <- UI.button #+ [string "Accept"]
  noBtn  <- UI.button #+ [string "Decline"]

  on UI.click yesBtn $ \_ -> liftIO $ sendClientMsg env CMAcceptRematch
  on UI.click noBtn  $ \_ -> liftIO $ sendClientMsg env CMDeclineRematch

  void $ getBody (appWindow env) #+ [element dlg, element yesBtn, element noBtn]

-- Reset lại trạng thái GUI về giai đoạn đặt tàu (sau khi rematch)
resetLocalPlacement :: GameEnv -> Element -> IO ()
resetLocalPlacement env statusMsg = do
    putStrLn "[DEBUG] Resetting local placement state after rematch."
    writeIORef (shipsPlacedRef env) []
    writeIORef (isPlacingRef env) True
    writeIORef (currentShipTypeRef env) T.Carrier
    writeIORef (isHorizontalRef env) True

    -- Reset game state
    gs <- readIORef (gameStateRef env)
    let cleared = G.emptyBoard
    let newGs = gs { G.p1 = (G.p1 gs){ G.board = cleared, G.ships = [], G.ready = False }
                   , G.p2 = (G.p2 gs){ G.board = cleared, G.ships = [], G.ready = False }
                   , G.phase = G.PlacingShips
                   , G.winner = Nothing }
    writeIORef (gameStateRef env) newGs

    -- Đọc UI components
    mGV <- readIORef (gameViewElem env)
    pBoard <- readIORef (p1CellsRef env)
    oBoard <- readIORef (p2CellsRef env)

    case mGV of
      Nothing -> putStrLn "[WARN] No game view element found."
      Just gv -> do
        let wnd = appWindow env
        runUI wnd $ do
          void $ element statusMsg
            # set text "Rematch started - place your ships again!"
            # set UI.style [("color", "orange")]

          -- render lại board và rebind clicks
          renderAllBoards env gv pBoard oBoard newGs
          liftIO $ rebindPlacementClicks env


placeShipAt :: GameEnv -> (Int, Int) -> T.ShipType -> Bool -> UI ()
placeShipAt env (r,c) shipType isH = do
    placed <- liftIO $ readIORef (shipsPlacedRef env)
    if length placed >= 5
      then return ()
      else case S.placeShipPositions (r,c) isH shipType of
        Nothing -> liftIO $ putStrLn " Out of bounds."
        Just positions -> do
          let overlaps = any (\s -> any (`elem` S.positions s) positions) placed
          if overlaps
            then liftIO $ putStrLn " Overlap detected."
            else do
              let sid = length placed + 1
                  newShip = S.Ship sid shipType positions
              gs <- liftIO $ readIORef (gameStateRef env)
              mpid <- liftIO $ readIORef (playerIdRef env)
              let pid = fromMaybe 1 mpid
              case G.placeShipForPlayer gs pid newShip of
                Nothing -> liftIO $ putStrLn " Cannot place ship (conflict)."
                Just gs' -> liftIO $ do
                  modifyIORef' (shipsPlacedRef env) (const (newShip:placed))
                  writeIORef (gameStateRef env) gs'
                  putStrLn $ "[OK] Placed " ++ show shipType ++ " at " ++ show (r,c)


rebindPlacementClicks :: GameEnv -> IO ()
rebindPlacementClicks env = do
    putStrLn " Rebinding placement clicks..."
    wnd <- pure (appWindow env)
    p1Cells <- readIORef (p1CellsRef env)
    let coords = [ (r, c, cell) | (r, row) <- zip [0..] p1Cells
                                , (c, cell) <- zip [0..] row ]
    runUI wnd $ do
        forM_ coords $ \(r, c, cell) -> do
            on UI.click cell $ \_ -> do
                isPlacing <- liftIO $ readIORef (isPlacingRef env)
                when isPlacing $ do
                    shipType <- liftIO $ readIORef (currentShipTypeRef env)
                    horiz <- liftIO $ readIORef (isHorizontalRef env)
                    placeShipAt env (r, c) shipType horiz

-- Gửi một tin nhắn (ClientMsg) đã được mã hóa JSON tới Server
sendClientMsg :: GameEnv -> ClientMsg -> IO ()
sendClientMsg env cm = do
    msock <- readIORef (sockRef env)
    case msock of
      Nothing -> putStrLn "Network: not connected, cannot send message"
      Just sock -> do
          let msgData = encode cm <> BL.singleton '\n'
          putStrLn $ "Sending to server: " ++ show cm
          NSB.sendAll sock (BL.toStrict msgData)

-- Tạo giao diện Đăng nhập / Đăng ký
createLoginView :: GameEnv -> IORef [[Element]] -> IORef [[Element]] -> UI Element
createLoginView env p1CellsRef p2CellsRef = do
    -- Ô nhập IP
    ipLabel <- UI.span #+ [string "Server IP: "]
    ipInput <- UI.input # set UI.value "127.0.0.1"
    connectBtn <- UI.button #+ [string "Connect to Server"]
    connectStatus <- UI.span # set text "Not connected."

    -- Ô username + password
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
        , UI.div #. "ip-connect" #+
            [ element ipLabel, element ipInput, element connectBtn, element connectStatus ]
        , UI.div #. "login-form" #+
            [ element usernameInput, element passwordInput, element loginBtn, element signupBtn ]
        , element status
        ]

    -- Nút Connect
    on UI.click connectBtn $ \_ -> do
        host <- get value ipInput
        liftIO $ do
            putStrLn $ "Attempting to connect to server " ++ host ++ ":3000"
            void $ forkIO $ tryConnectAndListen env host "3000"
        element connectStatus # set text ("Connecting to " ++ host ++ "...")

    let addUserToEnv uid name =
          liftIO $ modifyIORef' (loggedInUsers env) $
              \us -> if any ((== uid) . fst) us then us else us ++ [(uid, name)]

    -- Nút Sign up
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
                    mGameView <- liftIO $ readIORef (gameViewElem env)
                    case mGameView of
                      Just gv -> showElement gv
                      Nothing -> return ()
                    gs <- liftIO $ readIORef (gameStateRef env)
                    p1Cells <- liftIO $ readIORef p1CellsRef
                    p2Cells <- liftIO $ readIORef p2CellsRef
                    case mGameView of
                      Just gv -> void $ renderAllBoards env gv p1Cells p2Cells gs
                      Nothing -> return ()

    -- Nút Login
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
                mGameView <- liftIO $ readIORef (gameViewElem env)
                case mGameView of
                  Just gv -> showElement gv
                  Nothing -> return ()
                gs <- liftIO $ readIORef (gameStateRef env)
                p1Cells <- liftIO $ readIORef p1CellsRef
                p2Cells <- liftIO $ readIORef p2CellsRef
                case mGameView of
                  Just gv -> void $ renderAllBoards env gv p1Cells p2Cells gs
                  Nothing -> return ()

    return loginDiv



-- Tạo giao diện chính của trò chơi (2 bàn cờ, các nút điều khiển)
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

  statusMsg <- UI.div # set UI.id_ "status-msg" #. "status-msg" # set text "Select a ship to place"
  sunkPanel <- UI.div # set UI.id_ "sunk-panel" #. "sunk-panel" # set text ""

  -- Các nút trong dialog Quit/Rematch
  rematchBtn <- UI.button #. "control-btn" # set UI.id_ "rematch-btn" # set text "Rematch"

  logoutBtn  <- UI.button # set UI.id_ "logout-btn"  # set text "Logout"
  cancelBtn  <- UI.button # set UI.id_ "cancel-btn"  # set text "Cancel"

  quitDialog <- UI.div # set UI.id_ "quit-dialog" #. "quit-dialog" # set style [("display","none")] #+
    [ UI.div #. "quit-dialog-content" #+
        [ UI.h3 # set text "What would you like to do?"
        , element rematchBtn
        , element logoutBtn
        , element cancelBtn
        ]
    ]

  -- ban đầu ẩn nút Quit
  void $ element quitBtn # set style [("display","none")]

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

  -- truyền trực tiếp elements của dialog buttons vào setupGameEvents
  setupGameEvents env gameDiv rotateBtn readyBtn quitBtn statusMsg
    carrierBtn battleshipBtn cruiserBtn submarineBtn destroyerBtn
    myBoardCells targetBoardCells p1CellsRef p2CellsRef
    quitDialog rematchBtn logoutBtn cancelBtn

  return gameDiv


-- Tạo DOM cho một bàn cờ 10x10
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
    
    -- Thêm ID vào container và set position: relative
    container <- UI.div #. "board-container"
                       # set UI.id_ (boardId ++ "-container") -- <--- DÒNG NÀY QUAN TRỌNG
                       #+
        [ UI.h2 # set text title
        , element table
        ]
    return (container, cellsMatrix)

-- Hàm chính: Gắn các trình xử lý sự kiện (event handlers) cho tất cả các nút và ô cờ
setupGameEvents :: GameEnv -> Element ->
                   Element -> Element -> Element -> Element ->
                   Element -> Element -> Element -> Element -> Element ->
                   [[Element]] -> [[Element]] ->
                   IORef [[Element]] -> IORef [[Element]] ->
                   Element -> Element -> Element -> Element -> UI ()
setupGameEvents env gameDiv rotateBtn readyBtn quitBtn statusMsg
                carrierBtn battleshipBtn cruiserBtn submarineBtn destroyerBtn
                myBoardCells targetBoardCells p1CellsRef p2CellsRef
                quitDialog rematchBtn logoutBtn cancelBtn = do

    currentShipTypeRef <- liftIO $ newIORef T.Carrier
    shipsPlacedRef     <- liftIO $ newIORef ([] :: [S.Ship])
    isHorizontalRef    <- liftIO $ newIORef True
    isPlacingRef       <- liftIO $ newIORef True

    let setStatus txt = void $ element statusMsg # set text txt

    -- Render lại cả 2 bàn cờ và cập nhật trạng thái nút Quit
    let renderAndUpdate = do
          gs <- liftIO $ readIORef (gameStateRef env)
          -- render boards
          p1c <- liftIO $ readIORef p1CellsRef
          p2c <- liftIO $ readIORef p2CellsRef
          void $ renderAllBoards env gameDiv p1c p2c gs
          -- show/hide quit button depending on phase
          case G.phase gs of
            G.GameOver -> void $ element quitBtn # set style [("display","block")]
            _          -> void $ element quitBtn # set style [("display","none")]

    -- initial status
    setStatus "Choose a ship to place, then click on your board."

    -- Gắn sự kiện cho 5 nút chọn tàu (Carrier, Battleship, Cruiser, Submarine, Destroyer)
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

    -- placing on my board
    forM_ [(r,c) | r <- [0..9], c <- [0..9]] $ \(r,c) -> do
        let cell = myBoardCells !! r !! c
        on UI.click cell $ \_ -> do
            isPlacing <- liftIO $ readIORef isPlacingRef
            when isPlacing $ do
              currentShipType <- liftIO $ readIORef currentShipTypeRef
              isH <- liftIO $ readIORef isHorizontalRef
              placed <- liftIO $ readIORef shipsPlacedRef
              if length placed >= 5
                then setStatus "Bạn đã đặt đủ 5 tàu."
                else case S.placeShipPositions (r,c) isH currentShipType of
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
                          Just _ -> do
                            liftIO $ sendClientMsg env (CMPlaceShip sid (show currentShipType) (r,c) isH)
                            mpid <- liftIO $ readIORef (playerIdRef env)
                            case mpid of
                              Nothing -> setStatus $ "Placed (request sent) " ++ show currentShipType ++ " at " ++ show (r,c) ++ ", awaiting server confirmation..."
                              Just vid -> do
                                gs <- liftIO $ readIORef (gameStateRef env)
                                case G.placeShipForPlayer gs vid newShip of
                                  Nothing -> setStatus "Local placement failed (conflict)."
                                  Just gs' -> do
                                    liftIO $ modifyIORef' shipsPlacedRef (const newPlaced)
                                    liftIO $ writeIORef (gameStateRef env) gs'
                                    setStatus $ "Placed (request sent) " ++ show currentShipType ++ " at " ++ show (r,c)
                                    void renderAndUpdate
                                    when (length newPlaced >= 5) $ do
                                      liftIO $ writeIORef isPlacingRef False
                                      setStatus "All ships placed — press Ready to start the game."
                          Nothing -> do
                            gs <- liftIO $ readIORef (gameStateRef env)
                            mpid <- liftIO $ readIORef (playerIdRef env)
                            let vid = fromMaybe 1 mpid
                            case G.placeShipForPlayer gs vid newShip of
                              Nothing -> setStatus "Failed to place ship into local game state (conflict)."
                              Just gs' -> do
                                liftIO $ writeIORef shipsPlacedRef newPlaced
                                liftIO $ writeIORef (gameStateRef env) gs'
                                setStatus $ "Placed " ++ show currentShipType
                                void renderAndUpdate
                                when (length newPlaced >= 5) $ do
                                  liftIO $ writeIORef isPlacingRef False
                                  setStatus "All ships placed — press Ready to start the game."

    -- Gắn sự kiện cho nút "Ready"
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
                gs0 <- liftIO $ readIORef (gameStateRef env)
                mpid <- liftIO $ readIORef (playerIdRef env)
                let vid = fromMaybe 1 mpid
                    gsReady = G.setPlayerReady gs0 vid
                liftIO $ writeIORef (gameStateRef env) gsReady
                liftIO $ writeIORef isPlacingRef False
                setStatus "You are ready (local). Waiting for opponent..."
                void renderAndUpdate

    -- Gắn sự kiện cho nút "Quit"
    on UI.click quitBtn $ \_ -> do
      void $ element quitDialog # set style [("display","block")]
      return ()


    -- Gắn sự kiện cho nút "Rematch"
    on UI.click rematchBtn $ \_ -> do
      -- all IO actions must be lifted into UI monad
      liftIO $ putStrLn "UI: rematchBtn clicked - sending CMRequestRematch."

      msock <- liftIO $ readIORef (sockRef env)   -- <-- sửa backtick + bọc liftIO
      case msock of
        Nothing -> do
          liftIO $ putStrLn "UI: Cannot request rematch - no socket connection."
          void $ element statusMsg # set text "Not connected to server. Please reconnect."
        Just _  -> do
          liftIO $ sendClientMsg env CMRequestRematch
          liftIO $ putStrLn "UI: CMRequestRematch sent."
          void $ element statusMsg # set text "Rematch requested. Waiting for opponent..."

    -- Gắn sự kiện cho nút "Logout"
    on UI.click logoutBtn $ \_ -> do
      msock <- liftIO $ readIORef (sockRef env)
      case msock of
        Just _  -> liftIO $ sendClientMsg env CMQuit
        Nothing -> return ()

      -- Reset toàn bộ dữ liệu
      liftIO $ do
        writeIORef (targetMarksRef env) []
        writeIORef (sunkPositionsRef env) []
        writeIORef (playerIdRef env) Nothing
        writeIORef (gameStateRef env) G.initState
        writeIORef (sockRef env) Nothing

      void $ hideElement quitDialog
      void $ hideElement gameDiv
      void $ hideElement quitBtn

      mLoginElem <- liftIO $ readIORef (loginViewElem env)
      case mLoginElem of
        Just loginDiv -> do
          void $ showElement loginDiv
          -- reset lại nội dung input
          mU <- getElementById (appWindow env) "username-input"
          mP <- getElementById (appWindow env) "password-input"
          mS <- getElementById (appWindow env) "login-status"
          maybe (return ()) (\e -> void $ element e # set value "") mU
          maybe (return ()) (\e -> void $ element e # set value "") mP
          maybe (return ()) (\e -> void $ element e # set text "Please login.") mS
        Nothing -> liftIO $ putStrLn "logout: loginViewElem missing"

    -- Cancel: chỉ đóng dialog
    on UI.click cancelBtn $ \_ -> do
      void $ element quitDialog # set style [("display","none")]

    -- Gắn sự kiện click cho TẤT CẢ các ô trên "Target Grid"
    forM_ [(r,c) | r <- [0..9], c <- [0..9]] $ \(r,c) -> do
      let tcell = targetBoardCells !! r !! c
      on UI.click tcell $ \_ -> do
        gs <- liftIO $ readIORef (gameStateRef env)
        when (G.phase gs == G.Playing) $ do
          msock <- liftIO $ readIORef (sockRef env)
          case msock of
            Just _ -> do
              liftIO $ sendClientMsg env (CMFire (r,c))
              void $ element tcell # set UI.class_ "cell target-fired"
              setStatus $ "Fired at " ++ show (r,c) ++ ", waiting for result..."
            Nothing -> do
              let attacker = G.turn gs
                  (gs', res) = G.applyFire gs attacker (r,c)
              liftIO $ writeIORef (gameStateRef env) gs'
              case res of
                L.ShotMiss -> void $ element tcell # set UI.class_ "cell target-miss"
                _          -> void $ element tcell # set UI.class_ "cell target-hit"
              setStatus $ "Fired at " ++ show (r,c)
              void renderAndUpdate

    return ()


-- Hàm chính để vẽ lại cả 2 bàn cờ dựa trên GameState
renderAllBoards :: GameEnv -> Element -> [[Element]] -> [[Element]] -> G.GameState -> UI ()
renderAllBoards env _ myCells targetCells gs = do
    mpid <- liftIO $ readIORef (playerIdRef env)
    let wnd = appWindow env
    case mpid of
      Nothing -> do
        -- Nếu chưa có ID, render bảng rỗng
        let clearCells elems = forM_ (concat elems) $ \cell -> void $ element cell # set UI.class_ "cell"
        clearCells myCells
        clearCells targetCells
      Just viewer -> do
        let opponent = if viewer == 1 then 2 else 1
        
        -- Vẽ các ô (cell) như cũ (hit, miss, water)
        void $ renderBoardElems env myCells gs viewer
        void $ renderBoardElems env targetCells gs opponent

        -- 2. Tìm container và gọi renderShips
        -- Chúng ta chỉ vẽ SVG tàu của BẢN THÂN (viewer)
        mMyBoardContainer <- getElementById wnd "my-board-container"
        traverse_ (\container -> renderShips env container gs viewer "my-board" myCells) mMyBoardContainer

-- Vẽ các tàu SVG lên trên bàn cờ
renderShips :: GameEnv -> Element -> G.GameState -> Int -> String -> [[Element]] -> UI ()
renderShips env boardContainer gs owner boardId cellMatrix = do
    -- Kích thước 1 ô (cell) là 35px, theo file style.css
    let cellSize = 35 :: Double 
        -- Khoảng đệm (padding) 20px của .board-container
        containerPadding = 20 :: Double 
        -- Chiều cao tổng cộng của h2 title (estimate: khoảng 24px text + 10px margin = 34px)
        headerHeight = 34 :: Double

    -- Lấy danh sách tàu của người chơi (owner)
    let pState = if owner == 1 then G.p1 gs else G.p2 gs
        shipsToRender = G.ships pState

    -- Vẽ tàu mới
    forM_ shipsToRender $ \ship -> do
        let (r, c) = head (S.positions ship)
            len = T.shipSize (S.shipType ship)
            
            -- Suy luận hướng tàu từ 2 tọa độ đầu tiên
            (r1, c1) = head (S.positions ship)
            (r2, _c2) = (S.positions ship) !! 1
            isHorizontal = r2 == r1

        let (shipWidth, shipHeight) = if isHorizontal
              then (fromIntegral len * cellSize, cellSize)
              else (cellSize, fromIntegral len * cellSize)

        let sid = S.shipId ship
            shipElemId = "ship-" ++ show owner ++ "-" ++ show sid
        -- Nếu đã có element tàu cũ cùng id thì xóa nó trước
        mOld <- getElementById (appWindow env) shipElemId
        maybe (return ()) delete mOld

        let svgString = getShipSVG (S.shipType ship)

        -- Tính toán vị trí: padding + header + (cell row/col * cellSize)
        -- Các cell được sắp xếp trong bảng HTML, tính từ container padding
        let topPos  = containerPadding + headerHeight + (fromIntegral r * cellSize)
            leftPos = containerPadding + (fromIntegral c * cellSize)

        -- Tạo element SVG và áp style
        shipElement <- UI.div # set UI.id_ shipElemId #. "ship-svg" # set html svgString
        void $ element shipElement # set style
            [ ("position", "absolute")
            , ("top", show topPos ++ "px")
            , ("left", show leftPos ++ "px")
            , ("width", show shipWidth ++ "px")
            , ("height", show shipHeight ++ "px")
            ]
        
        -- Thêm tàu vào container
        void $ element boardContainer #+ [element shipElement]

renderBoardElems :: GameEnv -> [[Element]] -> G.GameState -> Int -> UI ()
renderBoardElems env elems gs owner = do
    let b = G.getPlayerBoard gs owner
    mpid <- liftIO $ readIORef (playerIdRef env)
    sunkMap <- liftIO $ readIORef (sunkPositionsRef env)
    let viewer = fromMaybe 1 mpid
        isMyFleet = owner == viewer
        isTargetGrid = owner /= viewer
        ownerSunkPositions = maybe [] id (lookup owner sunkMap)

    liftIO $ do
      tm <- readIORef (targetMarksRef env)
      let ownerTargetsCount = length (maybe [] id (lookup owner tm))
      putStrLn $ "DEBUG renderBoardElems: owner=" ++ show owner ++ ", viewer=" ++ show viewer ++ ", ownerTargetsCount=" ++ show ownerTargetsCount ++ ", ownerSunkCount=" ++ show (length ownerSunkPositions)

    forM_ (zip [0..] elems) $ \(r,row) ->
      forM_ (zip [0..] row) $ \(c,cell) -> do
      let mcell = B.getCell b (r,c)
      tm <- liftIO $ readIORef (targetMarksRef env)
      let ownerTargets = maybe [] id (lookup owner tm)
      case lookup (r,c) ownerTargets of
        Just markType -> case markType of
          "sunk" -> void $ element cell # set UI.class_ (if isTargetGrid then "cell target-sunk" else "cell hit")
          "hit"  -> void $ element cell # set UI.class_ (if isTargetGrid then "cell target-hit" else "cell hit")
          "miss" -> void $ element cell # set UI.class_ (if isTargetGrid then "cell target-miss" else "cell miss")
          _      -> void $ element cell # set UI.class_ "cell"
        Nothing -> do
          if (r,c) `elem` ownerSunkPositions
            then if isTargetGrid
                   then void $ element cell # set UI.class_ "cell target-sunk"
                   else void $ element cell # set UI.class_ "cell hit"
            else case mcell of
              Just T.Empty -> void $ element cell # set UI.class_ "cell"
              
              -- === ĐÂY LÀ THAY ĐỔI QUAN TRỌNG ===
              -- Không tô màu ".cell.ship" nữa, chỉ để là ".cell" (nước biển)
              -- Vì SVG sẽ được vẽ đè lên trên.
              Just (T.ShipPart _) -> void $ element cell # set UI.class_ "cell"
              -- === KẾT THÚC THAY ĐỔI ===
              
              Just T.Hit -> void $ element cell # set UI.class_ (if isMyFleet then "cell hit" else "cell target-hit")
              Just T.Miss -> void $ element cell # set UI.class_ (if isMyFleet then "cell miss" else "cell target-miss")
              _ -> void $ element cell # set UI.class_ "cell"


-- Tạm thời bỏ qua (dùng cho debug/offline)
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

-- Trả về chuỗi SVG cho từng loại tàu
getShipSVG :: T.ShipType -> String
getShipSVG T.Carrier =
    "<svg viewBox=\"0 0 150 30\" xmlns=\"http://www.w3.org/2000/svg\">\
    \  <rect x=\"0\" y=\"5\" width=\"150\" height=\"20\" rx=\"4\" ry=\"4\" fill=\"currentColor\"/>\
    \  <rect x=\"100\" y=\"0\" width=\"30\" height=\"30\" rx=\"2\" ry=\"2\" fill=\"currentColor\"/>\
    \</svg>"
getShipSVG T.Battleship =
    "<svg viewBox=\"0 0 120 30\" xmlns=\"http://www.w3.org/2000/svg\">\
    \  <rect x=\"0\" y=\"5\" width=\"120\" height=\"20\" rx=\"4\" ry=\"4\" fill=\"currentColor\"/>\
    \  <circle cx=\"30\" cy=\"15\" r=\"7\" fill=\"currentColor\" stroke=\"#334155\" stroke-width=\"2\"/>\
    \  <circle cx=\"90\" cy=\"15\" r=\"7\" fill=\"currentColor\" stroke=\"#334155\" stroke-width=\"2\"/>\
    \</svg>"
getShipSVG T.Cruiser =
    "<svg viewBox=\"0 0 90 30\" xmlns=\"http://www.w3.org/2000/svg\">\
    \  <path d=\"M 0 15 L 10 8 L 80 8 L 90 15 L 80 22 L 10 22 Z\" fill=\"currentColor\"/>\
    \  <rect x=\"35\" y=\"10\" width=\"20\" height=\"10\" rx=\"2\" ry=\"2\" fill=\"currentColor\" stroke=\"#334155\" stroke-width=\"1\"/>\
    \</svg>"
getShipSVG T.Submarine =
    "<svg viewBox=\"0 0 90 30\" xmlns=\"http://www.w3.org/2000/svg\">\
    \  <rect x=\"0\" y=\"7\" width=\"90\" height=\"16\" rx=\"8\" ry=\"8\" fill=\"currentColor\"/>\
    \  <rect x=\"35\" y=\"2\" width=\"20\" height=\"26\" rx=\"3\" ry=\"3\" fill=\"currentColor\"/>\
    \</svg>"
getShipSVG T.Destroyer =
    "<svg viewBox=\"0 0 60 30\" xmlns=\"http://www.w3.org/2000/svg\">\
    \  <path d=\"M 0 15 L 10 10 L 50 10 L 60 15 L 50 20 L 10 20 Z\" fill=\"currentColor\"/>\
    \</svg>"


-- Ẩn/hiện element
hideElement, showElement :: Element -> UI ()
hideElement e = void $ element e # set style [("display", "none")]
showElement e = void $ element e # set style [("display", "block")]
