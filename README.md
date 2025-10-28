# Functional_Programming_Battle_Ship

## Project Structure
```plaintext
├── app/
│   ├── client/
│   │   └── Main.hs         -- Client executable entrypoint
│   └── server/ 
│       └── Main.hs         -- Server executable entrypoint
│
├── src/
│   ├── Game/
│   │   ├── Board.hs       -- Board representation and operations
│   │   ├── Ship.hs        -- Ship types and placement logic
│   │   ├── Logic.hs       -- Game rules and shot mechanics
│   │   ├── Player.hs      -- Player state management
│   │   ├── State.hs       -- Game state and turn management
│   │   └── Types.hs       -- Common type definitions
│   │
│   ├── Network/
│   │   ├── Server.hs      -- Server socket and game management
│   │   ├── Client.hs      -- Client connection and message handling
│   │   └── Message.hs     -- Message protocol definitions
│   │
│   ├── Utils/
│   │   ├── Parser.hs      -- Input parsing utilities
│   │   ├── Serializer.hs  -- JSON encoding/decoding
│   │   └── Concurrency.hs -- Thread and synchronization
│   │
│   └── Config.hs          -- Application configuration
│
├── test/
│   ├── GameLogicSpec.hs   -- Game logic test suite
│   └── NetworkSpec.hs     -- Network protocol tests
│
├── data/
│   ├── sample_board.txt   -- Example board layouts
│   └── logs/              -- Server logs directory
│
├── stack.yaml             -- Stack build configuration
├── package.yaml           -- Package dependencies and settings
├── README.md             -- Project documentation
└── LICENSE               -- BSD3 license
```
