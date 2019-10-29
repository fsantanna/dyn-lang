module Dyn.Ifce where

import Debug.Trace
import Data.Bool                (bool)
import Data.Maybe               (fromJust)
import qualified Data.List as L (find, sort)
import qualified Data.Set  as S
import qualified Data.Map  as M
import Text.RawString.QQ

import Dyn.AST
import Dyn.Classes

-------------------------------------------------------------------------------

ifceFind :: [Ifce] -> ID_Ifce -> Ifce
ifceFind ifces ifc = fromJust $ L.find f ifces where
                      f :: Ifce -> Bool
                      f (Ifce (_,id,_,_)) = (id == ifc)

-- IEq -> [eq,neq]
ifceToDeclIds :: Ifce -> [ID_Var]
ifceToDeclIds (Ifce (_,_,_,dcls)) = map getId $ filter isDSig dcls where
                                      getId (DSig _ id _) = id

-- [...] -> ["IEq"] -> ["IEq","IOrd"] -- (sorted)
ifcesSups :: [Ifce] -> [ID_Ifce] -> [ID_Ifce]
ifcesSups ifces []  = []
ifcesSups ifces ids = L.sort $ ifcesSups ifces ids' ++ ids where
                        ids' = concatMap (f . (ifceFind ifces)) ids
                        f (Ifce (_,ifc,[],     _)) = []
                        f (Ifce (_,ifc,[(_,l)],_)) = l
                        f _ = error $ "TODO: multiple constraints"

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-- interface IEq for a
--  dIEq = Dict.IEq (eq,neq)              -- : declare instance dict if all defaults are implemented
--  <...>                                 -- : modify nested impls which become globals

ifceToDecls :: [Ifce] -> Ifce -> [Decl]
ifceToDecls ifces me@(Ifce (z,ifc_id,_,decls)) = dict ++ decls' where

  -- dIEq = Dict.IEq (eq,neq)
  -- (only if all methods are implemented)
  dict :: [Decl]
  dict = bool [] [datr] has_all_impls where
          datr = DAtr z (PWrite z ("d"++ifc_id)) (Where (z,f,[])) where
            f = EFunc z tz [] (Where (z,d,[]))
            d = ECall z (ECons z ["Dict",ifc_id])
                        (fromList $ map (EVar z) $ ifceToDeclIds me)

          has_all_impls = (length dsigs == length datrs) where
                            (dsigs, datrs) = declsSplit decls

  decls' = map (expandDecl ifces (ifc_id,[])) decls

-------------------------------------------------------------------------------

-- implemenation of IEq for Bool
-- implemenation of IEq for a where a is IXxx
--  dIEqBool = Dict.IEq (eq,neq) where    -- : declare instance dict with methods
--              <...>                     -- :   with nested impls to follow only visible here

implToDecls :: [Ifce] -> Impl -> [Decl]
implToDecls ifces (Impl (z,ifc,tp@(Type (_,_,cs)),decls)) = [dict] where

  -- dIEqBool = func -> Dict.IEq (eq,neq) where eq=<...> daIXxx=...;
  -- func b/c of HKT that needs a closure with parametric dictionary
  dict = DAtr z (PWrite z ("d"++ifc++toString' tp)) (Where (z,f,[])) where
          f = EFunc z tz [] (Where (z,d,decls'++[ups']))
          d = ECall z (ECons z ["Dict",ifc])
                      (fromList $ map (EVar z) $ ifceToDeclIds ifce)

  -- {daIXxx} // implementation of IOrd for a where a is IXxx
  ups' = DAtr z (fromList $ map (PWrite z) $ L.sort $ map ("da"++) imp_ids)
                (Where (z,EArg z,[]))

  toString' (Type (_, TData hr, _      )) = concat hr
  toString' (Type (_, TVar _,   [(_,l)])) = concat l

  -- eq = <...>
  decls' = map (expandDecl ifces (id,imp_ids)) decls where
            Ifce (_,id,_,_) = ifce    -- id:  from interface

  imp_ids = case cs of          -- ids: from instance constraints
              []      -> []
              [(_,l)] -> l
              _       -> error "TODO: multiple vars"

  ifce = fromJust $ L.find h ifces where
          h :: Ifce -> Bool
          h (Ifce (_,id,_,_)) = (id == ifc)

-------------------------------------------------------------------------------

-- [Ifce]:              known interfaces
-- (ID_ifce,[ID_Ifce]): iface constraint // impl extra constraints
-- Decl:                decl to expand
-- Decl:                expanded decl
expandDecl :: [Ifce] -> (ID_Ifce,[ID_Ifce]) -> Decl -> Decl

expandDecl ifces (ifc_id,imp_ids) (DSig z1 id1 (Type (z2,ttp2,cs2))) =
  DSig z1 id1 (Type (z2,ttp2,cs2')) where
    -- TODO: a?
    cs2' = ("a", ifcesSups ifces (ifc_id:imp_ids)) : cs2

-- IBounded: minimum/maximum
expandDecl _ _ decl@(DAtr _ _ (Where (_,econst,_))) | isConst econst = decl where
  isConst (EUnit  _)      = True
  isConst (ECons  _ _)    = True
  isConst (ETuple _ es)   = all isConst es
  isConst (ECall  _ f ps) = isConst f && isConst ps
  isConst _               = False

--  eq = func :: ((a,a) -> Bool) ->       -- : insert a is IEq/IXxx
--    ret where
--      <...>
--      ... = (p1,...pN)                  -- : restore original args
--      (fN,...,gN) = dN                  -- : restore iface functions from dicts
--      ((d1,...,dN), (p1,...,pN)) = ...  -- : split dicts / args from instance call
expandDecl ifces
           (ifc_id,imp_ids)
           (DAtr z1 e1
            (Where (z2,
              EFunc z3 (Type (z4,TFunc inp4 out4,cs4)) [] (Where (z5,e5,ds5)),
              ds2))) =
  DAtr z1 e1
    (Where (z2,
            EFunc z3 (Type (z4,TFunc inp4 out4,cs4NImps')) ups3' (Where (z5,e5,ds5')),
            ds2))
  where
    --  a where a is (IEq,IOrd)
    -- TODO: a?
    -- TODO: ctrsUnion
    cs4NImps' = ("a", ifcesSups ifces [ifc_id])         : cs4
    cs4YImps  = ("a", ifcesSups ifces (ifc_id:imp_ids)) : cs4

    -- {daIXxx} // implementation of IOrd for a where a is IXxx
    ups3' = map (\id -> (id,EUnit az)) $ L.sort $ map ("da"++) imp_ids

    --  <...>               -- original
    --  (f1,...,g1) = d1
    --  (fN,...,gN) = dN
    --  ... = args          -- AUTO
    --  ((d1,...,dN), args) = ...
    ds5' = ds5 ++ fsDicts5 ++ [
      DAtr z1 (PArg z1)                             (Where (z1,EVar z1 "args",[])),
      DAtr z1 (PTuple z1 [dicts5,PWrite z1 "args"]) (Where (z1,EArg z1,[]))
     ]

    -- [Dict.IEq (eq,neq) = daIEq]
    fsDicts5 :: [Decl]
    fsDicts5 = map f (dicts cs4YImps) where
      f :: (ID_Var,ID_Ifce,[ID_Var]) -> Decl
      f (var,ifc,ids) = DAtr z1 pat (Where (z1,exp,[])) where
        -- Dict.IEq (eq,neq)
        pat :: Patt
        pat = PCall z1 (PCons z1 ["Dict",ifc]) (fromList $ map (PWrite z1) ids)
        -- daIEq
        exp :: Expr
        exp = EVar z1 $ 'd':var++ifc

    -- (d1,...,dN)
    -- csNImps: exclude implementation constraints since dicts come from closure
    dicts5 :: Patt
    dicts5 = fromList $ map (PWrite z1) $ L.sort $ map (\(var,ifc,_) -> 'd':var++ifc) (dicts cs4NImps')
                                                  -- [daIEq,daIShow,dbIEq,...]

    -- [ (a,IEq,[eq,neq]), (a,IOrd,[...]), (b,...,...), ...]
    dicts :: TCtrs -> [(ID_Var,ID_Ifce,[ID_Var])]
    dicts cs = concatMap f cs where
      -- (a,[IEq,IShow]) -> [(a,IEq,[eq,neq]), (a,IOrd,[lt,gt,lte,gte]]
      f :: (ID_Var,[ID_Ifce]) -> [(ID_Var,ID_Ifce,[ID_Var])]
      f (var,ifcs) = map h $ map g ifcs where
                      h :: (ID_Ifce,[ID_Var]) -> (ID_Var,ID_Ifce,[ID_Var])
                      h (ifc,ids) = (var,ifc,ids)

      -- IEq -> (IEq, [eq,neq])
      g :: ID_Ifce -> (ID_Ifce,[ID_Var])
      g ifc = (ifc, ifceToDeclIds $ ifceFind ifces ifc)

expandDecl _ _ decl = error $ toString decl

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-- [Ifce]: known ifces
-- [Decl]: known DSig decls
-- Type:   expected type
-- [Decl]: decls to transform
-- [Decl]: transformed decls (maybe the same)
--
poly :: [Ifce] -> [Decl] -> Type -> [Decl] -> [Decl]

poly ifces dsigs xtp decls = map poly' $ map rec decls where

  -- recurse poly into other Decls
  rec :: Decl -> Decl
  rec d@(DSig _ _ _) = d
  rec (DAtr z1 (PWrite z2 id2) (Where (z3,e3,ds3))) =
    DAtr z1 (PWrite z2 id2) (Where (z3,e3,ds3')) where
      ds3' = poly ifces dsigs' (dsigFind dsigs' id2) ds3
  -- TODO: other cases
  rec (DAtr z1 pat2 (Where (z3,e3,ds3))) =
    DAtr z1 pat2 (Where (z3,e3,ds3')) where
      ds3' = poly ifces dsigs' (Type (az,TAny,cz)) ds3

  dsigs' = dsigs ++ filter isDSig decls

  -- handle poly

  poly' :: Decl -> Decl

  poly' d@(DSig _ _ _) = d

  -- xtp=Bool pat2=TODO e3=maximum 
  poly' (DAtr z1 pat2 (Where (z3,EVar z4 id4,ds3))) =
    DAtr z1 pat2 (Where (z3,EVar z4 id4,ds3'')) where
      ds3'' = bool ds3' ds3 (null tvars4)

      -- x :: Bool = maximum
      Type (_,TData xhr,_) = xtp

      -- maximum :: a where a is IBounded
      Type (_,ttp4,cs4) = dsigFind dsigs id4

      tvars4  = toVars ttp4 -- [a,...]
      [tvar4] = tvars4      -- a

      -- [("IBounded",...)]
      ifc_ids = snd $ fromJust $ L.find ((==tvar4).fst) cs4

      -- ["Dict.IBounded (min,max) = dIBoundedBool", ...]
      ds3' :: [Decl]
      ds3' = map f $
              -- [("IEq", "daIEqBool", (eq,neq)),...]
              zip3 ifc_ids dicts dclss
             where
              -- ["dIEqBool",...]
              dicts = map (\ifc -> "d"++ifc++concat xhr) ifc_ids
              -- [(eq,neq),...]
              dclss = map ifceToDeclIds $ map (ifceFind ifces) ifc_ids

              -- ("IEq", "daIEqBool", (eq,neq)) -> Dict.IEq (eq,neq) = daIEqBool
              f (ifc,dict,dcls) =
                DAtr z1 (PCall z1 (PCons z1 ["Dict",ifc]) (fromList $ map (PWrite z1) dcls))
                        (Where (z1, ECall z1 (EVar z1 dict) (EUnit z1), []))

  poly' d@(DAtr _ _ _) = d

{-
poly' ifces dsigs xtp_out@(Type (_,xttp_out,_)) whe@(Where (z1,call@(ECall z2 (EVar z3 id3) expr2),ds1)) =
  if null tvars3 then
    whe
  else
    Where (z1, ECall z2 (EVar z3 id3) expr2', ds1++ds1')
  where
    -- eq :: (a,a) -> Bool
    Type (_,ttp3,cs3) = dsigFind dsigs id3

    tvars3  = toVars ttp3 -- [a]
    [tvar3] = tvars3      -- a

    -- [("IEq",...)]
    -- a is IEq
    ifc_ids = snd $ fromJust $ L.find ((==tvar3).fst) cs3

    -- ["dIEqBool",...]
    dicts = map (\ifc -> "d"++ifc++concat xhr) ifc_ids

    -- eq (Bool,Boot)
    -- a is Bool
    TFunc inp3 out3 = ttp3
    [("a",xhr)] = ttpMatch inp3 (toTType expr2)
    -- TODO: xttp_out vs out3

    -- eq(dIEqBool,...)
    expr2' = ETuple z2 [(fromList $ map (EVar z2) dicts), expr2]

    ds1' :: [Decl]
    ds1' = map f $
            -- [("IEq", "daIEqBool", (eq,neq)),...]
            zip3 ifc_ids dicts dclss
           where
            -- [(eq,neq),...]
            dclss = map ifceToDeclIds $ map (ifceFind ifces) ifc_ids

            -- ("IEq", "daIEqBool", (eq,neq)) -> Dict.IEq (eq,neq) = daIEqBool
            f (ifc,dict,dcls) =
              DAtr z1 (PCall z1 (PCons z1 ["Dict",ifc]) (fromList $ map (PWrite z1) dcls))
                      (Where (z1, ECall z1 (EVar z1 dict) (EUnit z1), []))


    --traceShow ("XTP",toString xtp, "FUNC",toString $ dsigFind dsigs id3, "PS",toString $ toTType expr) whe

poly' _ _ _ whe = whe
-}
-------------------------------------------------------------------------------

dsigFind :: [Decl] -> ID_Var -> Type
dsigFind dsigs id = case L.find f dsigs of
                      Nothing            -> Type (az,TAny,cz)
                      Just (DSig _ _ tp) -> tp
                    where
                      f :: Decl -> Bool
                      f (DSig _ x _) = (id == x)

toTType :: Expr -> TType
toTType (ECons  _ hr) = TData hr
toTType (ETuple _ es) = TTuple $ map toTType es
toTType e = error $ "toTType: " ++ toString e

toVars :: TType -> [ID_Var]
toVars ttp = S.toAscList $ aux ttp where
  aux TAny            = S.empty
  aux TUnit           = S.empty
  aux (TData _)       = S.empty
  aux (TVar id)       = S.singleton id
  aux (TFunc inp out) = S.union (aux inp) (aux out)
  aux (TTuple tps)    = S.unions (map aux tps)

-- (a,a) vs (Bool.True,Bool.False)  -> [(a,Bool)]
ttpMatch :: TType -> TType -> [(ID_Var,ID_Hier)]
ttpMatch ttp1 ttp2 = M.toAscList $ aux ttp1 ttp2 where
  aux :: TType -> TType -> M.Map ID_Var ID_Hier
  aux (TVar id)    (TData (hr:_)) = M.singleton id [hr]
  aux (TTuple ts1) (TTuple ts2)   = M.unionsWith f $ map (\(x,y)->aux x y) (zip ts1 ts2)
                                      where f hr1 hr2 | hr1==hr2 = hr1
  aux x y = error $ show (x,y)
