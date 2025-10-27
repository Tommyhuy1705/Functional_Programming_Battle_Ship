# Functional_Programming_Battle_Ship

## Project Structure
```plaintext
battleship/
│
├── app/
│   ├── MainServer.hs      -- entrypoint chạy server
│   ├── MainClient.hs      -- entrypoint chạy client
│
├── src/
│   ├── Game/
│   │   ├── Board.hs       -- định nghĩa bàn chơi, kích thước, trạng thái ô
│   │   ├── Ship.hs        -- định nghĩa tàu (loại, kích thước, vị trí)
│   │   ├── Logic.hs       -- logic trò chơi: bắn, trúng, chìm, thắng/thua
│   │   ├── Player.hs      -- định nghĩa người chơi, lượt đi
│   │   ├── State.hs       -- quản lý toàn bộ trạng thái game (Board + Player)
│   │
│   ├── Network/
│   │   ├── Server.hs      -- quản lý socket server (listen, accept client)
│   │   ├── Client.hs      -- socket client (connect, gửi/nhận)
│   │   ├── Message.hs     -- định nghĩa message protocol (JSON / text)
│   │
│   ├── Utils/
│   │   ├── Parser.hs      -- parse input từ client
│   │   ├── Serializer.hs  -- encode/decode message
│   │   ├── Concurrency.hs -- thread, MVar, sync game turn
│   │
│   └── Config.hs          -- cấu hình chung: port, IP, constants
│
├── test/
│   ├── GameLogicSpec.hs   -- unit test logic game
│   ├── NetworkSpec.hs     -- test message + connection
│
├── data/
│   ├── sample_board.txt   -- data mẫu (testing)
│   ├── logs/              -- log server
│
├── stack.yaml
├── package.yaml
├── README.md
└── LICENSE
```
