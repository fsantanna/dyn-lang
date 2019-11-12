module Dyn.Ifce (apply,ifceFind,ifceToDeclIds,ifcesSups) where

import Debug.Trace
import Data.Bool                (bool)
import Data.Maybe               (fromJust)
import qualified Data.List as L (find, sort, groupBy)

import Dyn.AST
import Dyn.Classes
import qualified Dyn.Parser as P
import qualified Dyn.Eval   as E

-------------------------------------------------------------------------------

apply :: Prog -> Prog -> Prog
apply _ globs = map globFromDecl $ dicts globs ++ concatMap f globs where
                  f :: Glob -> [Decl]  -- [Decl] w/o Ifce/Impl/Gens
                  f (GDecl dcl) = expandGen globs dcl
                  f (GData dat) = []
                  f (GIfce ifc) = ifceToDecls ifc
                  f (GImpl imp) = implToDecls globs imp

dicts globs = --traceShowSS $
  map toDict        $   -- [ ds_IEnum=..., ... ]
  map toCons        $   -- [ (IEnum, Cons((K.Unit,dIEnumUnit), Cons(..., Nil))) ]
  L.groupBy sameIfc $   -- [ [(IEnum,...),(IEnum,...)], [(IEq,...)] ]
  map toTuple       $   -- [ (IEnum, Cons(K.Unit,dIEnumUnit)), (IEnum, Cons(K.Bool,dIEnumBool), ...]
  globsToImpls      $   -- [IEnum for Unit, IEq for XXX, IEnum for Bool, ...]
  globs where

  toDict :: (ID_Ifce,Expr) -> Decl
  toDict (ifc,cons) = DAtr pz (PWrite pz ("ds_"++ifc))
                       (ExpWhere (pz,[], cons))

  toCons :: [(ID_Ifce,Expr)] -> (ID_Ifce,Expr)
  toCons l = (fst $ head l,
              foldr f (ECons pz ["List","Nil"]) $ map snd l)
             where
              f tup acc = ECall pz (ECons pz ["List","Cons"])
                                   (ETuple pz [tup,acc])

  toTuple (Impl (_,ifc,_,tp,_)) = (ifc,tup) where
                                    tp' = tpToString' tp
                                    tup = ETuple pz [c1,c2] where
                                            c1 = ECons pz ["Key",tp']
                                            c2 = EVar  pz ("d"++ifc++tp')
  sameIfc (ifc1,_) (ifc2,_) = (ifc1 == ifc2)

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

ifceFind :: [Glob] -> ID_Ifce -> Ifce
ifceFind globs ifc = fromJust $ L.find f (globsToIfces globs) where
                      f :: Ifce -> Bool
                      f (Ifce (_,id,_,_)) = (id == ifc)

-- IEq -> [eq,neq]
ifceToDeclIds :: Ifce -> [ID_Var]
ifceToDeclIds (Ifce (_,_,_,dcls)) = map getId $ filter isDSig dcls where
                                      getId (DSig _ id _ _) = id

-- [...] -> ["IEq"] -> ["IEq","IOrd"] -- (sorted)
ifcesSups :: [Glob] -> [ID_Ifce] -> [ID_Ifce]
ifcesSups _     []  = []
ifcesSups globs ids = L.sort $ ifcesSups globs ids' ++ ids where
                        ids' = concatMap (f . (ifceFind globs)) ids
                        f (Ifce (_,_,Ctrs l,_)) = l

tpToString' (TData hr [])  = concat hr
--tpToString' (TData hr tps) = concat hr ++ concatMap tpToString' tps
--tpToString' (TVar _)       = concat cs
tpToString' TUnit          = "Unit"
tpToString' x = error $ show x

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

--  interface IEq for a
--    eq :: (a,a) -> Bool                       -- only abstract methods
--
-- expand to
--
--  data Dict.IEq (typeof(eq))
--  eq' = func -> fst ...                       -- same as below
--  eq' = func -> eq where Dict.IEq (eq) = ...  -- same as above
--  eq :: (a,a) -> Bool where a is IEq          -- global prototype (include IEq)

ifceToDecls :: Ifce -> [Decl]
ifceToDecls me@(Ifce (z,ifc_id,ctrs,decls)) = wraps ++ decls' where

  -- Same for constant (minimum) and function (eq).
  -- eq' = func -> eq where Dict.IEq (eq) = ...
  wraps = map toWrap meIds where
    toWrap id = DAtr z (PWrite z (id++"'"))
                       (ExpWhere (z,[],
                          EFunc z cz TAny [] (ExpWhere (z,[dict],EVar z id))))
     where
      dict = DAtr z pats exp where
              pats = fromList $ map f $ L.sort $ ifc_id : getCtrs ctrs where
                      f id | (id==ifc_id) = patt
                           | otherwise    = PAny z
              patt = PCall z (PCons z ["Dict",ifc_id])
                             (fromList $ map f meIds) where
                      f x = bool (PAny z) (PWrite z id) (id==x)
              exp  = ExpWhere (z,[],EArg z)

  meIds = ifceToDeclIds me

  -- include ":: where a is IEq"
  decls' = map f decls where
            f (DSig z id (Ctrs []) tp) = DSig z id (Ctrs [ifc_id]) tp

-------------------------------------------------------------------------------

-- implemenation of IEq for Bool
-- implemenation of IEq for a where a is IXxx
--  dIEqBool = Dict.IEq (eq) where    -- : declare instance dict with methods
--              <...>                 -- :   with nested impls to follow only visible here

implToDecls :: [Glob] -> Impl -> [Decl]
implToDecls globs (Impl (z,ifc,Ctrs [],tp,decls)) =
  [DAtr z (PWrite z ("d"++ifc++tpToString' tp))
          (ExpWhere (z,decls,
            ECall z (ECons z ["Dict",ifc])
                    (fromList $ map (EVar z) $ ifceToDeclIds $ ifceFind globs ifc)))]

-------------------------------------------------------------------------------

expandGen :: [Glob] -> Decl -> [Decl]

--  neq = func :: ((a,a) -> Bool) where a is IEq ->
--    not (eq ...)
--
--    expand to
--
--  neq :: ((a,a) -> Bool) where a is IEq
--  neq' = func ->
--    let dIEqa = ... in              -- receives dict
--      func :: <tp/cs> {daIEq} ->    -- same as above but as a closure with fixed dict
--        not (eq ...)                -- Poly.hs will then translate to ((eq' daIEq) ...)

expandGen globs (DAtr z1 (PWrite pz pid)
                  (ExpWhere (z2, [],
                    EFunc z3 (Ctrs cs3) tp3 [] whe3))) | not (null cs3) =
  [
    DSig z1 pid (Ctrs cs3) tp3,                   -- neq ::
    DAtr z1 (PWrite pz (pid++"'"))                -- neq' =
    (ExpWhere (z2, [],
      EFunc z2 cz TAny [] $
        ExpWhere (z2, [letDicts],            -- let dIEqa = ...
          EFunc z3 (Ctrs cs3') tp3 ups3' whe3)))
  ]
  where
    -- { dIEqa }
    ups3'    = map (\id -> ("d"++id++"a",EUnit z3)) $ cs3'
    letDicts = DAtr z2  -- (dIEqa,...) = ...
                (fromList $ map (\id -> PWrite z2 $ "d"++id++"a") cs3')
                (ExpWhere (z2,[],EArg z2))
    cs3'     = ifcesSups globs cs3

expandGen _ decl = [decl]
