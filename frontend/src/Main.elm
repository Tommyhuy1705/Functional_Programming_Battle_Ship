module Main exposing (main)

import Browser
import Html exposing (Html, button, div, input, li, text, ul, table, tr, td, attribute)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Json.Decode as Decode
import Json.Encode as Encode
import WebSocket


-- MODEL

type alias Model =
    { host : String
    , port : String
    , connected : Bool
    , messages : List String
    , rowInput : String
    , colInput : String
    }

init : () -> ( Model, Cmd Msg )
init _ =
    ( { host = "localhost"
      , port = "8080"
      , connected = False
      , messages = []
      , rowInput = "0"
      , colInput = "0"
      }
    , Cmd.none
    )


-- MESSAGES

type Msg
    = Connect
    | Connected
    | Receive String
    | SendFire
    | UpdateRow String
    | UpdateCol String
    | NoOp


-- UPDATE

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Connect ->
            let
                module Main exposing (main)

                import Browser
                import Html exposing (Html, button, div, input, li, text, ul)
                import Html.Attributes exposing (placeholder, value)
                import Html.Events exposing (onClick, onInput)
                import Json.Encode as Encode
                import String
                import WebSocket


                -- MODEL

                type alias Model =
                    { host : String
                    , port : String
                    , messages : List String
                    , rowInput : String
                    , colInput : String
                    }


                init : () -> ( Model, Cmd Msg )
                init _ =
                    ( { host = "localhost"
                      , port = "8080"
                      , messages = []
                      , rowInput = "0"
                      , colInput = "0"
                      }
                    , Cmd.none
                    )


                -- MESSAGES

                type Msg
                    = Receive String
                    | SendFire
                    | UpdateRow String
                    | UpdateCol String


                -- UPDATE

                update : Msg -> Model -> ( Model, Cmd Msg )
                update msg model =
                    case msg of
                        Receive s ->
                            ( { model | messages = s :: model.messages }, Cmd.none )

                        SendFire ->
                            let
                                url = "ws://" ++ model.host ++ ":" ++ model.port
                                r = String.toInt model.rowInput |> Maybe.withDefault 0
                                c = String.toInt model.colInput |> Maybe.withDefault 0
                                payload = Encode.object
                                    [ ( "tag", Encode.string "CMFire" )
                                    , ( "fireTarget", Encode.list [ Encode.int r, Encode.int c ] )
                                    ]
                            in
                            ( model
                            , WebSocket.send url (Encode.encode 0 payload) |> Cmd.map (\_ -> Receive "(sent)")
                            )

                        UpdateRow s -> ( { model | rowInput = s }, Cmd.none )
                        UpdateCol s -> ( { model | colInput = s }, Cmd.none )


                -- SUBSCRIPTIONS

                subscriptions : Model -> Sub Msg
                subscriptions model =
                    let
                        url = "ws://" ++ model.host ++ ":" ++ model.port
                    in
                    WebSocket.listen url Receive


                -- VIEW

                view : Model -> Html Msg
                view model =
                    div []
                        [ div [] [ text ("WebSocket: " ++ model.host ++ ":" ++ model.port) ]
                        , div []
                            [ input [ placeholder "row", value model.rowInput, onInput UpdateRow ] []
                            , input [ placeholder "col", value model.colInput, onInput UpdateCol ] []
                            , button [ onClick SendFire ] [ text "Fire" ]
                            ]
                        , div [] [ text "Messages:" ]
                        , ul [] (List.map (\t -> li [] [ text t ]) model.messages)
                        ]


                -- MAIN

                main : Program () Model Msg
                main =
                    Browser.element
                        { init = init
                        , update = update
                        , subscriptions = subscriptions
                        , view = view
                        }
