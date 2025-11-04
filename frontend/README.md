Elm frontend for the Battleship game.

Build & run (requires Elm 0.19 installed):

1. cd frontend
2. elm make src/Main.elm --output=main.js
3. open index.html in your browser (or serve the folder with a static server)

Notes:
- This frontend connects to a WebSocket server at ws://localhost:8080 by default.
- The existing Haskell server in this repo uses raw TCP; to use this frontend you need a WebSocket adapter that translates websocket messages to the server protocol. You can add a small adapter in Haskell (using the `websockets` package) or modify the server to accept WebSocket connections.
