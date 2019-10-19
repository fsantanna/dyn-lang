module Dyn.ASTSpec (main,spec) where

import Test.Hspec

import Dyn.AST

main :: IO ()
main = hspec spec

spec = do

  describe "exprToString:" $ do
    it "a" $
      exprToString (EVar az "a") `shouldBe` "a"

  describe "dclToString:" $ do
    it "a :: () = b" $
      dclToString 0
        (Dcl (az, EVar az "a", Just tz,
          Just $ Where (az, EVar az "b", []))) `shouldBe` "a :: () = b"
    it "a :: () = b where\n  b=()" $
      dclToString 0
        (Dcl (az, EVar az "a", Just tz,
          Just $ Where (az, EVar az "b",
            [Dcl (az, EVar az "b", Just tz, Just $ Where (az, EUnit az,[]))])))
        `shouldBe` "a :: () = b where\n  b :: () = ()"

  describe "dclToString:" $ do
    it "b where b=a, a=()" $
      whereToString 0 (
        Where (az, EVar az "b", [
          Dcl (az, EVar az "b", Just tz, Just $ Where (az, EVar az "a",[])),
          Dcl (az, EVar az "a", Just tz, Just $ Where (az, EUnit az,[]))
        ]))
        `shouldBe` "b where\n  b :: () = a\n  a :: () = ()"

  describe "progToString:" $ do
    it "v" $
      progToString (Where (az, EVar az "v", [])) `shouldBe` "v"