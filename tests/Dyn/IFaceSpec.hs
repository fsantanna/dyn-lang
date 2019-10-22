{-# LANGUAGE QuasiQuotes #-}

module Dyn.IFaceSpec (main,spec) where

import Test.Hspec
import Text.RawString.QQ

import Dyn.AST
import Dyn.Parser
import Dyn.Eval

bool = [r|
  not = func ->
    case ... of
      Bool.False -> Bool.True
      Bool.True  -> Bool.False
    ;
  ;

  and = func ->
    case ... of
      (Bool.False, _) -> Bool.False
      (_, Bool.False) -> Bool.False
      _               -> Bool.True
    ;
  ;

  or = func ->
    case ... of
      (Bool.True, _)  -> Bool.True
      (_,         =y) -> y
    ;
  ;
|]

-- instance IEq (Bool)
ieq_bool = [r|
  -- Wrappers are closures with fixed "ieq_bool" dict
  eq_bool  = func -> eq (ieq_bool,x,y) where
              (x,y)  = ...
              (eq,_) = ieq_bool
             ;;
  neq_bool = func -> neq (ieq_bool,x,y) where
              (x,y)   = ...
              (_,neq) = ieq_bool
             ;;

-- Dict receives eq/neq methods.
--  - implements eq, uses default neq
--  - methods receive extra dict
  ieq_bool = (eq_bool_,neq_) where
    eq_bool_ = func ->
      or (and (x,y), (and (not x, not y))) where
        (_,x,y) = ...
      ;
    ;
  ;
|]

-- interface IEq(eq,neq)
ieq = [r|
  -- Methods are renamed to include "dict" param:
  --  - eq_ is not implemented
  --  - neq_ has a default implentation
  neq_ = func ->
    not (eq_ ((eq_,neq_),x,y)) where
      ((eq_,neq_),x,y) = ...
    ;
  ;
|]

main :: IO ()
main = hspec spec

spec = do

  describe "manual" $ do

    it "IEqualable: default neq" $
      run ([r|
main = v where  -- neq (eq(T,T), F)
  -- typesystem renames to concrete type methods
  v = neq_bool (eq_bool (Bool.True,Bool.True), Bool.False)
;

|] ++ ieq_bool ++ bool ++ ieq)
        `shouldBe` "Bool.True"

{-
    it "IEqualable/IOrderable" $
      run ([r|
main = v where  -- (T<=F, T>=T, F>F, F<T)
  v = ( lte_bool (Bool.True,  Bool.False),
        gte_bool (Bool.True,  Bool.True),
        gt_bool  (Bool.False, Bool.False),
        lt_bool  (Bool.False, Bool.True) )
;

  -- interface IOrderable
  lte_ = func ->
    or ( lt_ ((eq_,neq_),(lt_,lte_,gt_,gte_),x,y),
         eq_ ((eq_,neq_),x,y) )

interface IOrderable for a where (a is IEqualable) with
  func @<        : ((a,a) -> Bool)
  func @<= (x,y) : ((a,a) -> Bool) do return (x @< y) or (x === y) end
  func @>  (x,y) : ((a,a) -> Bool) do return not (x @<= y)         end
  func @>= (x,y) : ((a,a) -> Bool) do return (x @> y) or (x === y) end
end

implementation of IOrderable for Bool with
  func @< (x,y) : ((Bool,Bool) -> Bool) do
    if      (x, y) matches (Bool.False, Bool.False) then return Bool.False
    else/if (x, y) matches (Bool.False, Bool.True)  then return Bool.True
    else/if (x, y) matches (Bool.True,  Bool.False) then return Bool.False
    else/if (x, y) matches (Bool.True,  Bool.True)  then return Bool.False
    end
  end
end
|] ++ ieq_bool ++ bool)
        `shouldBe` "(Bool.False,Bool.True,Bool.False,Bool.True)"
-}
