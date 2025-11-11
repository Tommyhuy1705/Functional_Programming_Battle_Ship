# Battleship - Trò chơi Hải Chiến mạng (Haskell)

Dự án **Battleship** là một trò chơi hải chiến (Battleship Game) được xây dựng hoàn toàn bằng **ngôn ngữ lập trình hàm Haskell**, theo **mô hình client–server**.
Trò chơi cho phép **hai người chơi ở hai máy khác nhau** thi đấu qua **WebSocket** (hoặc TCP socket), với **logic kiểm soát trò chơi an toàn, xử lý song song (concurrency)** và **giao diện GUI tùy chọn** được phát triển bằng **Threepenny-GUI**.

Hệ thống được tổ chức rõ ràng gồm các module:

* **Game logic**: xử lý toàn bộ quy tắc đặt tàu, bắn, trúng/miss/sunk, kết thúc trò chơi.
* **Network layer**: quản lý giao tiếp Client ↔ Server qua JSON message (Aeson).
* **Database scaffold**: sẵn sàng tích hợp PostgreSQL hoặc SQLite cho hệ thống đăng nhập.
* **Concurrency control**: đảm bảo tính toàn vẹn trạng thái game thông qua `MVar` và `withGameLock`.

---

## Tính năng chính

* Kiến trúc **Client / Server độc lập** (Stack executables):
  `battleship-server`, `battleship-client`, `battleship-gui` (tùy chọn).
* Đặt tàu thủ công theo quy tắc tiêu chuẩn:

  | Loại tàu   | Ký hiệu | Kích thước |
  | ---------- | ------- | ---------- |
  | Carrier    | C       | 5          |
  | Battleship | B       | 4          |
  | Cruiser    | R       | 3          |
  | Submarine  | S       | 3          |
  | Destroyer  | D       | 2          |
* Kiểm tra va chạm và ranh giới khi đặt tàu.
* Hệ thống **CMReady/SMPhase**: client báo “ready”, server tự động chuyển sang phase *Playing* khi cả hai sẵn sàng.
* **Quản lý lượt (Turn Management)**:

  * Khi `ShotMiss` → đổi lượt.
  * Khi tất cả tàu đối phương bị chìm → broadcast `SMGameOver`.
* **Message JSON (Aeson)**: định nghĩa `ClientMsg` và `ServerMsg` giúp tương tác rõ ràng.
* **Xử lý song song an toàn** bằng `MVar` – đảm bảo trạng thái nhất quán giữa các client.
* **Scaffold Database**: hỗ trợ xác thực đăng nhập (Auth) và lưu trữ thông tin người dùng.

---

## Cấu trúc dự án

```
Functional_Programming_Battle_Ship/
├── app/
│   ├── client/
│   │   └── Main.hs                 # Client entrypoint (battleship-client)
│   ├── server/
│   │   └── Main.hs                 # Server entrypoint (battleship-server)
│   └── gui/
│       └── Main.hs                 # GUI app (battleship-gui) - optional
│
├── src/
│   ├── Database/
│   │   ├── Auth.hs                 # Auth API, session helpers (module Database.Auth)
│   │   └── Users.hs                # User model / DB access (module Database.Users)
│   │
│   ├── Game/
│   │   ├── Board.hs                # Board representation, cell types, utils
│   │   ├── Ship.hs                 # Ship types, sizes, placement helpers
│   │   ├── Logic.hs                # Game rules: fireAt, hit/miss/sunk detection
│   │   ├── Player.hs               # Player state, board wrapper
│   │   ├── State.hs                # Global GameState, placeShipForPlayer, ready, winner
│   │   └── Types.hs                # Common types: Pos, ShipType, Orientation, Cell
│   │
│   ├── Network/
│   │   ├── Server.hs               # Server socket, client management, game loop
│   │   ├── Client.hs               # Client socket helpers
│   │   └── Message.hs              # ClientMsg / ServerMsg types (JSON), GamePhase
│   │
│   ├── Utils/
│   │   ├── Parser.hs               # Parse CLI commands (place, fire, ready)
│   │   ├── Serializer.hs           # Aeson serialization helpers for GameState/messages
│   │   ├── Concurrency.hs          # GameLock (MVar) and withGameLock
│   │   └── Parallel.hs             # Small concurrency utilities (helper)
│   │
│   ├── Config.hs                   # Configuration: port, host, board size, constants
│   └── Paths_battleship.hs         # auto-generated
│
├── database/                       # repository-level DB scaffolding (non-Haskell)
│   ├── README.md                   # hướng dẫn DB & login setup
│   ├── schema.sql                  # example SQL schema for users table
│   ├── users_sample.json           # optional sample users for local tests
│   └── notes.md                    # notes: use postgres/sqlite + bcrypt recommendations
│
├── test/
│   ├── Spec.hs                     # test suite entrypoint (hspec)
│   ├── GameLogicSpec.hs            # unit tests for game logic
│   └── NetworkSpec.hs              # tests for message serialization / network logic
│
├── data/
│   ├── sample_board.txt            # sample board layout (text)
│   └── logs/                       # server logs
│
├── stack.yaml
├── package.yaml
├── battleship.cabal
├── README.md
└── LICENSE
```

---

## Cài đặt

### 1. Clone repository:

```bash
git clone https://github.com/Tommyhuy1705/Functional_Programming_Battle_Ship.git
cd Functional_Programming_Battle_Ship
```

### 2. Cài đặt Stack:

Tải và cài đặt Stack tại [https://docs.haskellstack.org](https://docs.haskellstack.org)

### 3. Build project:

```bash
stack build
```

### 4. Chạy server:

```bash
stack exec battleship-server
# hoặc chỉ định port:
stack exec battleship-server -- --port 3000
```

### 5. Chạy client (ở 2 terminal khác nhau để chơi mạng):

```bash
stack exec battleship-client
# hoặc:
stack exec battleship-client -- localhost 3000
```

### 6. Chạy test:

```bash
stack test
```

---

## Thiết lập Database & Đăng nhập

Thư mục `src/Database` đã có scaffold sẵn cho hệ thống đăng nhập qua PostgreSQL.

Các bước cấu hình:

1. Cài đặt PostgreSQL.
2. Tạo database và bảng `users` (xem file `database/schema.sql`).
3. Cấu hình `.env`:

   ```
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=battleship
   DB_USER=postgres
   DB_PASS=yourpassword
   ```
4. Hệ thống sử dụng `dotenv` để load biến môi trường.
5. Mật khẩu được hash bằng **bcrypt (cryptonite)**.
6. Có thể mở rộng hỗ trợ `sqlite-simple` nếu cần.

---

## Cách chơi (CLI client)

### Bước 1: Đặt tàu

Khi vào game, server gửi `SMGamePhase = PlacingShips`.
Dùng lệnh:

```
place <id> <type> <row> <col> <orient>
```

Ví dụ:

```
place 1 Carrier 0 0 H
place 2 Battleship 2 3 V
```

### Bước 2: Sẵn sàng

Sau khi đặt đủ tất cả tàu, nhập:

```
ready
```

### Bước 3: Lượt chơi

Server thông báo lượt của bạn qua `SMYourTurn`.

Bắn:

```
fire <row> <col>
```

Server phản hồi:

* `SMResult { result = Hit | Miss | Sunk }`
* `SMUpdateBoard` — cập nhật bảng
* `SMGameOver { winner = <id> }` — kết thúc trò chơi

---

## Kiểm thử & Kết quả

* Có test cơ bản cho `Game.Logic` và message serialization trong `test/`.
* Game Over detection được xác nhận qua broadcast `SMGameOver`.
* Bạn có thể mở rộng test cases bằng cách thêm vào `test/Spec.hs`.

---

## Đóng góp

Bạn có thể tham gia phát triển:

* Bổ sung test unit cho các trạng thái đặc biệt (đặt tàu sai, bắn trùng, v.v.).
* Mở rộng Database login/session.
* Tích hợp GUI đẹp hơn với Threepenny.
* Thêm logging và reconnect.

---

## 🚀 Hướng phát triển tương lai

* Matchmaking nhiều phòng (multi-room).
* Tối ưu concurrency để hỗ trợ nhiều game cùng lúc.
* Tích hợp cloud deploy (Heroku, Render, hoặc AWS).

---

## Kiến trúc tổng quan

```text
           ┌───────────────────────────────┐
           │       Battleship Server       │
           │  - GameState Manager (MVar)   │
           │  - WebSocket Handler          │
           │  - Turn Controller            │
           └─────────────┬─────────────────┘
                         │
        WebSocket JSON   │
                         │
     ┌───────────────────┴─────────────────────┐
     │                                         │
┌────▼─────────────────────┐             ┌─────▼───────┐
│ Client A│                │             │ Client B    │
│  (Player 1)              │             │ (Player 2)  │
│  Threepenny GUI / CLI    │             │  CLI / GUI  │
└──────────────────────────┘             └─────────────┘
```

---

## Acknowledgments

Dự án sử dụng các thư viện Haskell mã nguồn mở:

* `aeson`, `network`, `websockets`, `stm`, `async`
* `cryptonite`, `postgresql-simple`, `dotenv`
* `threepenny-gui` (GUI)
* `QuickCheck` (test)

---

## Giấy phép

Dự án phân phối theo giấy phép **BSD3 License** — tự do sử dụng và chỉnh sửa cho mục đích học tập và nghiên cứu.

---
