{-# LANGUAGE QuasiQuotes #-}

module Dyn.PolyIfceSpec (main,spec) where

import Test.Hspec
import Text.RawString.QQ

import Dyn.AST
import Dyn.Parser
import Dyn.Eval
import Dyn.Prelude hiding (ieq,iord,ieq_bool,iord_bool)
import Dyn.Ifce

main :: IO ()
main = hspec spec

spec = do

  describe "IEq" $ do

    it "IEq: default eq" $
      run ([r|  -- neq (eq(T,T), F)
main = neq (dIEq, eq (dIEq,Bool.True,Bool.True), Bool.False) where
  Dict.IEq (eq,neq) = dIEq
;
|] ++ bool ++ ieq)
        `shouldBe` "Bool.True"

    it "IEq: (eq ((T,F),(F,T)), eq ((T,F),(T,F))" $
      run ([r|
main = (x,y) where
  x = eq (dIEq, (Bool.True,Bool.False), (Bool.False,Bool.True))
  y = eq (dIEq, (Bool.True,Bool.False), (Bool.True,Bool.False))
  Dict.IEq (eq,neq) = dIEq
;

implementation of IEq for Bool with
  eq = func ->
    or (and (x,y), (and (not x, not y))) where
      (_,x,y) = ...
    ;
  ;
;
|] ++ bool ++ ieq)
        `shouldBe` "(Bool.False,Bool.True)"

    it "IEq: overrides eq (dieq_bool)" $
      run ([r|
main = v where  -- neq (eq(T,T), F)
  v = neq (dIEq, eq (dIEq,Bool.True,Bool.True), Bool.False)
  Dict.IEq (eq,neq) = dIEq
;
|] ++ ieq_bool ++ bool ++ ieq)
        `shouldBe` "Bool.True"

    it "XXX: IEq/IOrd" $
      run ([r|
main = v where  -- (T<=F, T>=T, F>F, F<T)
  v = ( lte (dIEqBool, dIOrdBool, Bool.True,  Bool.False),
        gte (dIEqBool, dIOrdBool, Bool.True,  Bool.True),
        gt  (dIEqBool, dIOrdBool, Bool.False, Bool.False),
        lt  (dIEqBool, dIOrdBool, Bool.False, Bool.True) )
  Dict.IEq  (eq,neq)        = dIEqBool
  Dict.IOrd (lt,lte,gt,gte) = dIOrdBool
;
|] ++ iord_bool ++ ieq_bool ++ bool ++ iord ++ ieq)
        `shouldBe` "(Bool.False,Bool.True,Bool.False,Bool.True)"

{-
    it "implementation of IEq for a where a is IXxx" $
      run ([r|
main = eq (Dict.IEq (eq,neq),Xxx,Xxx) where
  Dict.IEq (eq,neq) = ieq_ixxx ixxx_xxx      -- higher-kinded types (HKT)?
;

ieq_ixxx = func -> -- ixxx -> ieq
  Dict.IEq (eq,neq) where
    eq = func {f} ->  -- :: (ieq_xxx,a,a) -> Bool where a is IXxx
      eq (Dict.IEq (eq,neq), f ((f),x), f ((f),y)) where
        Dict.IEq (eq,neq) = dieq_bool
        (_,x,y)  = ...
      ;
    ; where
      (f) = ...
    ;
  ;
;

ixxx_xxx = f where
  f = func -> -- :: (ixxx_xxx,X) -> Bool
    case x of
      Xxx -> Bool.True
    ; where
      (_,x) = ...
    ;
  ;
;
|] ++ ieq_bool ++ bool ++ ieq)
        `shouldBe` "Bool.True"

    it "f = func :: ((a -> Int) where a is IEq) {a,b} -> eq (x,x)" $
      run ([r|
main = f (ieq_nat, one)
f = func ->
  eq (Dict.IEq (eq,neq),x,x) where
    (Dict.IEq (eq,neq), x) = ...
  ;
;
|] ++ prelude)
          `shouldBe` "Bool.True"
-}