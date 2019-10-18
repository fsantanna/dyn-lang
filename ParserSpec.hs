{-# LANGUAGE QuasiQuotes #-}

module ParserSpec where

import Test.Hspec

import qualified Text.Parsec as P (eof, parse)
import Text.Parsec.String (Parser)

import Dyn.Parser
import Dyn.AST

fromRight (Right x) = x

parse :: Parser a -> String -> Either String a
parse rule input =
  case P.parse (rule <* P.eof) "" input of
    (Right v) -> Right v
    (Left  v) -> Left (show v)

main :: IO ()
main = hspec $ do

  describe "tokens:" $ do
    describe "comm:" $ do
      it "-- xxx " $
        parse tk_comm "-- xxx "
          `shouldBe` Right ()
    describe "var:" $ do
      it "xxx" $
        parse tk_var "xxx "
          `shouldBe` Right "xxx"

  describe "expr:" $ do
    it "xxx" $
      parse expr_var "xxx"
        `shouldBe` Right (EVar az{pos=(1,1)} "xxx")
    it "(())" $
      parse expr "(())"
        `shouldBe` Right (EUnit az{pos=(1,2)})

  describe "toString:" $ do
    describe "expr_unit:" $ do
      it "()" $
        (exprToString 0 $ fromRight $ parse expr_unit "()")
          `shouldBe` "()"
    describe "expr_var:" $ do
      it "xxx" $
        (exprToString 0 $ fromRight $ parse expr_var "xxx")
          `shouldBe` "xxx"
    describe "expr_tuple:" $ do
      it "(xxx,yyy)" $
        (exprToString 0 $ fromRight $ parse expr_tuple "(xxx, yyy)")
          `shouldBe` "(xxx,yyy)"
    describe "expr:" $ do
      it "()" $
        (exprToString 0 $ fromRight $ parse expr "()")
          `shouldBe` "()"
    describe "expr:" $ do
      it "(())" $
        (exprToString 0 $ fromRight $ parse expr "(())")
          `shouldBe` "()"
