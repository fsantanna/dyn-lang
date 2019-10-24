module Dyn.ASTSpec (main,spec) where

import Test.Hspec

import Dyn.AST

main :: IO ()
main = hspec spec

spec = do

  describe "exprToString:" $ do
    it "a" $
      exprToString 0 (EVar az "a") `shouldBe` "a"

  describe "declToString:" $ do
    it "a :: () = b" $
      declToString 0
        (Decl (az, PWrite az "a", Just tz,
          Just $ Where (az, EVar az "b", []))) `shouldBe` "a :: () = b"
    it "a :: () = b where\n  b=()" $
      declToString 0
        (Decl (az, PWrite az "a", Just tz,
          Just $ Where (az, EVar az "b",
            [Decl (az, PWrite az "b", Just tz, Just $ Where (az, EUnit az,[]))])))
        `shouldBe` "a :: () = b where\n  b :: () = ()\n;"

  describe "declToString:" $ do
    it "b where b=a, a=()" $
      whereToString 0 (
        Where (az, EVar az "b", [
          Decl (az, PWrite az "b", Just tz, Just $ Where (az, EVar az "a",[])),
          Decl (az, PWrite az "a", Just tz, Just $ Where (az, EUnit az,[]))
        ]))
        `shouldBe` "b where\n  b :: () = a\n  a :: () = ()\n;"

  describe "progToString:" $ do
    it "v" $
      progToString (Where (az, EVar az "v", [])) `shouldBe` "v"
