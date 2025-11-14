module NetworkSpec where

import Test.Hspec
import Network.Message
import Network.Server
import Network.Client
import Utils.Serializer

main :: IO ()
main = hspec $ do
    describe "Network Protocol" $ do
        it "should correctly serialize and deserialize messages" $ do
            -- TODO: Thêm test case cho mã hóa/giải mã tin nhắn
            pendingWith "Test not implemented"

        it "should handle client connections properly" $ do
            pendingWith "Test not implemented"

        it "should properly encode game state" $ do
            pendingWith "Test not implemented"