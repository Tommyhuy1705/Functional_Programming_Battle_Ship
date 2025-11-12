# Battleship (Haskell Network Game)

`Battleship (Haskell Network Game)` là một phiên bản lập trình của trò chơi Chiến hạm (Battleship) kinh điển, được xây dựng hoàn toàn bằng ngôn ngữ lập trình hàm **Haskell**.

Dự án này thể hiện một kiến trúc client-server rõ ràng, nơi máy chủ hoạt động như một nguồn quản lý trạng thái duy nhất (**authoritative server**). Máy chủ chịu trách nhiệm xử lý toàn bộ logic của ván đấu, xác thực các hành động, và đồng bộ hóa trạng thái cho hai người chơi thông qua mạng.

Điểm nổi bật của dự án là việc tách biệt logic trò chơi (các hàm pure trong `Game/Logic.hs`) khỏi các hiệu ứng (effects) của hệ thống mạng và quản lý trạng thái, đồng thời sử dụng các cấu trúc đồng thời (concurrency) của Haskell như `MVar` để đảm bảo an toàn dữ liệu.

## 1\. Kiến trúc Hệ thống

Dự án được xây dựng dưới dạng một gói (package) `stack` duy nhất, cung cấp ba tệp thực thi (executables) riêng biệt, thể hiện rõ ràng sự phân tách giữa các thành phần.

### 1.1. Máy chủ (Server) - `battleship-server`

Máy chủ là trung tâm xử lý, có toàn quyền quyết định logic game.

  * **Networking:** Sử dụng **TCP Sockets** tiêu chuẩn (từ thư viện `network`) để giao tiếp. Máy chủ chấp nhận tối đa hai kết nối. Mọi kết nối tiếp theo sẽ bị từ chối cho đến khi có một client ngắt kết nối.
  * **State Management:** Trạng thái của toàn bộ ván đấu (`GameState`) được lưu trữ trong một `MVar` (`GameLock`). Mọi hành động (đặt tàu, bắn) đều phải đi qua `withGameLock` để đảm bảo các cập nhật diễn ra một cách nguyên tử (atomic), tránh race conditions.
  * **Game Lifecycle:** Máy chủ quản lý toàn bộ vòng đời của trận đấu qua các giai đoạn (phases): `WaitingPlayers`, `PlacingShips`, `Playing`, và `GameOver`.
  * **Logic Handler:** Máy chủ nhận các thông điệp JSON (`ClientMsg`), xử lý chúng (ví dụ: `CMPlaceShip`, `CMFire`), cập nhật `GameState`, và phát lại kết quả (`ServerMsg`) cho các client liên quan.
  * **Features:** Tích hợp sẵn logic xử lý ngắt kết nối (`isClientAlive`, `handleDisconnect`) và hệ thống đấu lại (rematch).

### 1.2. Máy khách CLI (Client) - `battleship-client`

Một máy khách "mỏng" (thin client) hoạt động trong terminal.

  * **Concurrency:** Chạy hai luồng (threads): một luồng chính (`clientLoop`) để nhận lệnh từ người dùng (ví dụ: `fire 1 2`) và một luồng nền (`receiverLoop`) để lắng nghe và in thông điệp từ server (ví dụ: `SMYourTurn`, `SMResult`).
  * **Giao thức:** Gửi và nhận các thông điệp JSON (`ClientMsg`/`ServerMsg`) đã được định nghĩa.

### 1.3. Máy khách GUI (GUI Client) - `battleship-gui`

Một máy khách đồ họa, giàu tính năng hơn được xây dựng bằng `Threepenny-GUI`.

  * **Rendering:** Vẽ bàn cờ (`myBoard`, `targetBoard`) bằng HTML/CSS và quản lý các sự kiện click.
  * **Local State:** Sử dụng `IORef` để quản lý trạng thái giao diện cục bộ (ví dụ: tàu đang chọn để đặt, client ID của người chơi).
  * **Networking:** Tương tự như client CLI, nó kết nối đến cùng một server, gửi `ClientMsg` (ví dụ: khi click vào ô để bắn) và nhận `ServerMsg` để cập nhật giao diện (ví dụ: đổi màu ô thành `target-hit`).
  * **Auth Scaffold:** GUI tích hợp một hệ thống xác thực người dùng *cục bộ* (đăng nhập/đăng ký) sử dụng `Database/Users.hs` và `Database/Auth.hs`.

-----

## 2\. Công nghệ Nổi bật

| Thành phần | Công nghệ | Mục đích |
| :--- | :--- | :--- |
| **Ngôn ngữ** | **Haskell** (GHC) | Ngôn ngữ lập trình chính cho toàn bộ dự án. |
| **Build** | **Stack** | Quản lý phụ thuộc, biên dịch và chạy các tệp thực thi. |
| **Network** | **`network`** | Cung cấp API Socket cấp thấp cho giao tiếp **TCP**. |
| **Serialization** | **`aeson`** | Mã hóa (encode) và giải mã (decode) các gói tin mạng sang định dạng **JSON**. |
| **Concurrency** | **`Control.Concurrent`** | Sử dụng `MVar` (`GameLock`) để quản lý trạng thái đồng thời và `forkIO` để xử lý nhiều client. |
| **GUI** | **`threepenny-gui`** | Thư viện Functional Reactive Programming (FRP) để xây dựng giao diện web-UI. |
| **Database** | **`postgresql-simple`** | Cung cấp kết nối và truy vấn đến cơ sở dữ liệu PostgreSQL. |
| **Authentication** | **`cryptonite`** / **`base64-bytestring`** | Sử dụng **PBKDF2-SHA256** để băm và xác thực mật khẩu an toàn (thay vì bcrypt). |
| **Configuration** | **`dotenv`** | Tải thông tin nhạy cảm (như credentials của DB) từ tệp `.env`. |
| **Testing** | **`hspec`** | Framework để viết unit test và integration test. |

-----

## 3\. Tính năng Cốt lõi

  * **Kiến trúc Client-Server 1v1:** Toàn bộ logic được xác thực bởi server, client chỉ là giao diện hiển thị.
  * **Dual Clients:** Hỗ trợ cả client **CLI** (`battleship-client`) cho trải nghiệm cổ điển và client **GUI** (`battleship-gui`) cho trải nghiệm trực quan.
  * **Vòng đời Game (Game Lifecycle):** Quản lý trạng thái rõ ràng: `WaitingPlayers` -\> `PlacingShips` (client đặt tàu) -\> `Playing` (bắn theo lượt) -\> `GameOver`.
  * **Quản lý Lượt (Turn-Based):** Server kiểm soát chặt chẽ lượt chơi; chỉ người chơi có lượt (`turn`) mới có thể thực hiện `CMFire`. Lượt chỉ được chuyển khi bắn trượt (`ShotMiss`).
  * **Logic Đặt tàu:** Server xác thực vị trí đặt tàu (`CMPlaceShip`), kiểm tra va chạm với tàu khác (`placeShip`) và kiểm tra ngoài biên (`placeShipPositions`).
  * **Hệ thống Đấu lại (Rematch):** Sau khi game kết thúc (`SMGameOver`), người chơi có thể gửi `CMRequestRematch`. Server sẽ chờ cả hai người chơi đồng ý (`CMAcceptRematch`) trước khi reset game về `PlacingShips`.
  * **Xử lý Ngắt kết nối:** Server chủ động kiểm tra (`isClientAlive`) và dọn dẹp (`handleDisconnect`) các client đã ngắt kết nối, cho phép người chơi mới tham gia.
  * **Nền tảng Xác thực:** Cung cấp sẵn các module `Database.Users` và `Database.Auth` sử dụng **PostgreSQL** và băm **PBKDF2** để quản lý người dùng, sẵn sàng tích hợp vào server.

-----

## 4\. Giao thức Mạng (Network Protocol)

  * **Transport:** **TCP**
  * **Format:** **Newline Delimited JSON (NDJSON)**. Mỗi thông điệp Aeson được encode và gửi đi, theo sau là một ký tự xuống dòng (`\n`).

### Client to Server (`ClientMsg`)

  * `CMPlaceShip`: Gửi thông tin (loại tàu, tọa độ, hướng) để đặt một con tàu.
  * `CMReady`: Thông báo client đã đặt xong tàu và sẵn sàng bắt đầu.
  * `CMFire`: Bắn vào một tọa độ (`Pos`) trên bàn cờ đối thủ.
  * `CMRequestRematch`: Yêu cầu chơi lại sau khi ván đấu kết thúc.
  * `CMAcceptRematch`: Đồng ý yêu cầu chơi lại từ đối thủ.
  * `CMDeclineRematch`: Từ chối yêu cầu chơi lại.
  * `CMQuit`: Thông báo client chủ động ngắt kết nối.

### Server to Client (`ServerMsg`)

  * `SMWelcome`: Gửi khi kết nối thành công, cấp cho client một `playerId` (1 hoặc 2).
  * `SMGamePhase`: Thông báo sự thay đổi trạng thái game (ví dụ: chuyển từ `PlacingShips` sang `Playing`).
  * `SMYourTurn` / `SMOpponentTurn`: Thông báo lượt chơi hiện tại.
  * `SMUpdateBoard`: Gửi trạng thái bàn cờ mới nhất của người chơi (thường sau khi bị bắn).
  * `SMResult`: Gửi kết quả của một cú bắn (`Hit`, `Miss`, `Sunk`), bao gồm cả thông tin chi tiết nếu tàu bị chìm (`resShipType`, `resShipPositions`).
  * `SMGameOver`: Thông báo game kết thúc và ID của người chiến thắng.
  * `SMRematchRequested`: Thông báo cho client rằng đối thủ đã yêu cầu chơi lại.
  * `SMError`: Gửi một thông báo lỗi (ví dụ: "Not your turn").

-----

## 5\. Cấu trúc Thư mục

```
Functional_Programming_Battle_Ship/
├── app/
│   ├── client/
│   │   └── Main.hs           # Entrypoint cho Client CLI (battleship-client)
│   ├── server/
│   │   └── Main.hs           # Entrypoint cho Server (battleship-server)
│   └── gui/
│       ├── Main.hs           # Entrypoint cho Client GUI (battleship-gui)
│       └── static/css/       # CSS cho giao diện GUI
│           └── style.css
│
├── src/
│   ├── Database/
│   │   ├── Auth.hs           # Logic xác thực, quản lý session
│   │   ├── connect.hs        # Helper kết nối PostgreSQL (sử dụng dotenv)
│   │   └── Users.hs          # Model User, logic hash PBKDF2, truy vấn DB
│   │
│   ├── Game/
│   │   ├── Board.hs          # Định nghĩa Board, initBoard, get/setCell
│   │   ├── Logic.hs          # Logic game PURE: fireAt, allSunk
│   │   ├── Player.hs         # (Dường như đã cũ) Định nghĩa Player
│   │   ├── Ship.hs           # Định nghĩa Ship, ShipType, logic đặt tàu
│   │   ├── State.hs          # Định nghĩa GameState, PlayerState, và các hàm cập nhật
│   │   └── Types.hs          # Các kiểu dữ liệu cơ bản (Pos, Cell, ShipType)
│   │
│   ├── Network/
│   │   ├── Client.hs         # Logic cho CLI Client (send/receive)
│   │   ├── Message.hs        # Định nghĩa các gói tin ClientMsg, ServerMsg
│   │   └── Server.hs         # Logic chính của Server (quản lý client, game loop)
│   │
│   ├── Utils/
│   │   ├── Concurrency.hs    # Định nghĩa GameLock (MVar) và helper
│   │   ├── Parallel.hs       # Helper chạy IO song song
│   │   ├── Parser.hs         # (Chưa hoàn thiện) Parser cho input
│   │   └── Serializer.hs     # (Không dùng) Helper encode/decode GameState
│   │
│   └── Config.hs             # Hằng số (Port, Host, Kích thước Board)
│
├── data/
│   └── sample_board.txt      # Dữ liệu mẫu
│
├── test/
│   ├── Spec.hs               # Test suite chính (Hspec)
│   ├── GameLogicSpec.hs      # Unit test cho Game.Logic
│   └── NetworkSpec.hs        # Unit test cho Network.Message
│
├── .env                      # File cấu hình database (bị ẩn)
├── package.yaml              # Định nghĩa package (Stack)
├── battleship.cabal          # (Tự động sinh)
├── stack.yaml                # Cấu hình Stack (resolver lts-24.17)
└── README.md                 (Tệp này)
```

-----

## 6\. Cài đặt & Khởi chạy

### Yêu cầu

1.  **Stack:** Cần cài đặt Haskell Tool Stack. (Dự án sử dụng resolver `lts-24.17`).
2.  **PostgreSQL:** Cần một server PostgreSQL đang chạy (dành cho tính năng đăng nhập của GUI).
3.  **Thư viện C PostgreSQL:** Bạn có thể cần cài đặt thư viện phát triển C cho PostgreSQL (ví dụ: `libpq-dev` trên Ubuntu/Debian) để `postgresql-simple` có thể biên dịch. `stack.yaml` đã có sẵn đường dẫn cho Windows.

### Bước 1: Cấu hình Database

Tạo một tệp tên là `.env` ở thư mục gốc của dự án, dựa trên tệp `.env`:

```ini
user=tên_user_postgres
password=mật_khẩu_postgres
host=localhost
port=5432
dbname=postgres
pool_mode=session
```

Khi bạn chạy `battleship-gui` lần đầu và đăng ký, bảng `users` sẽ được tự động tạo (nhờ `ensureSchema` trong `Database/Users.hs`).

### Bước 2: Build dự án

```bash
stack build
```

### Bước 3: Chạy Server

Mở một terminal và chạy:

```bash
# Server sẽ chạy trên cổng 3000
stack exec battleship-server
```

Bạn sẽ thấy thông báo: `Server listening on port 3000`.

### Bước 4: Chạy Client (2 người chơi)

Bạn có thể chọn 1 trong 2 cách sau (hoặc kết hợp cả hai):

#### Lựa chọn A: Dùng Client CLI (Terminal)

Mở **hai** cửa sổ terminal khác nhau và chạy lệnh sau ở mỗi cửa sổ:

```bash
stack exec battleship-client
```

#### Lựa chọn B: Dùng Client GUI (Web)

Mở **hai** cửa sổ terminal khác nhau và chạy lệnh sau ở mỗi cửa sổ:

```bash
# Client GUI 1 (sẽ chạy ở http://localhost:8023)
stack exec battleship-gui
```

*Lưu ý: Threepenny-GUI có thể xung đột cổng nếu chạy 2 tiến trình. Nếu client thứ 2 báo lỗi "port already in use", bạn sẽ cần sửa `jsPort = Just 8023` trong `app/gui/Main.hs` thành một cổng khác (ví dụ: 8024) cho client thứ 2.*

Mở trình duyệt và truy cập `http://localhost:8023` (cho client 1) và `http://localhost:8024` (cho client 2).

-----

## 7\. Cách chơi (Sử dụng Client CLI)

1.  **Kết nối:** Ngay khi chạy `battleship-client`, bạn sẽ tự động kết nối đến server. Server sẽ gửi `SMWelcome { playerId = 1 }` cho người chơi đầu tiên và `... { playerId = 2 }` cho người thứ hai.

2.  **Đặt tàu (Phase: `PlacingShips`):**
    Server thông báo `SMGamePhase { smPhase = PlacingShips }`. Bạn phải đặt 5 con tàu. Sử dụng cú pháp: `place <id> <type> <r> <c> <orient>`.

      * `<id>`: Một số duy nhất (ví dụ: 1, 2, 3, 4, 5).
      * `<type>`: `Carrier`, `Battleship`, `Cruiser`, `Submarine`, `Destroyer`.
      * `(r, c)`: Tọa độ (hàng, cột) từ 0-9.
      * `<orient>`: `H` (ngang) hoặc `V` (dọc).

    *Ví dụ:*

    ```
    place 1 Carrier 0 0 H
    place 2 Battleship 2 0 V
    place 3 Cruiser 4 4 H
    place 4 Submarine 6 1 V
    place 5 Destroyer 8 8 H
    ```

3.  **Sẵn sàng:**
    Sau khi đặt đủ 5 tàu, gõ lệnh `ready`. Server sẽ chờ cả hai người chơi gửi `CMReady`.

4.  **Chơi (Phase: `Playing`):**
    Khi cả hai sẵn sàng, server gửi `SMGamePhase { smPhase = Playing }`.

      * Nếu là lượt bạn, server gửi `SMYourTurn`.
      * Gõ `fire <r> <c>` để bắn. (Ví dụ: `fire 0 0`).
      * Server sẽ trả về `SMResult` (ví dụ: "Hit", "Miss", "Sunk").
      * Nếu bắn trượt (`Miss`), server sẽ gửi `SMOpponentTurn` cho bạn và `SMYourTurn` cho đối thủ.
      * Nếu bắn trúng (`Hit` hoặc `Sunk`), bạn được giữ lượt.

5.  **Kết thúc (Phase: `GameOver`):**
    Khi bạn bắn chìm tàu cuối cùng, server gửi `SMGameOver { winner = <id_cua_ban> }`.

6.  **Đấu lại:**
    Gõ `rematch` để yêu cầu chơi lại.

      * Nếu đối thủ cũng gõ `rematch` (hoặc `CMAcceptRematch`), game sẽ reset về `PlacingShips`.
      * Nếu đối thủ từ chối, server sẽ báo `SMRematchDeclined`.

-----

## 8\. Giấy phép

Dự án phân phối theo giấy phép **BSD3 License** — tự do sử dụng và chỉnh sửa cho mục đích học tập và nghiên cứu.
