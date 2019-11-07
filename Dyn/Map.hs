module Dyn.Map where

import Debug.Trace
import Data.Bool    (bool)

import Dyn.AST
import Dyn.Classes

-------------------------------------------------------------------------------

type MapFs = ( ([Ifce]->Ctrs->[Decl]->Decl->[Decl]),
               ([Ifce]->Ctrs->[Decl]->Type->Expr->Expr),
               ([Ifce]->Ctrs->[Decl]->Patt->Patt) )
fDz _ _ _   d = [d]
fEz _ _ _ _ e = e
fPz _ _ _   p = p

-------------------------------------------------------------------------------

mapDecls :: MapFs -> [Ifce] -> Ctrs -> [Decl] -> [Decl] -> [Decl]
mapDecls fs ifces ctrs dsigs decls = concatMap (mapDecl fs ifces ctrs dsigs') decls
  where
    dsigs' = dsigs ++ filter isDSig decls

mapDecl :: MapFs -> [Ifce] -> Ctrs -> [Decl] -> Decl -> [Decl]
mapDecl fs@(fD,_,_) ifces ctrs dsigs decl@(DSig _ _ _ _) = fD ifces ctrs dsigs decl
mapDecl fs@(fD,_,_) ifces ctrs dsigs (DAtr z pat whe)    = fD ifces ctrs dsigs $ DAtr z pat' whe'
  where
    (_,pat') = mapPatt  fs ifces ctrs dsigs TAny pat
    whe'     = mapWhere fs ifces ctrs dsigs (toType dsigs pat) whe

-------------------------------------------------------------------------------

mapWhere :: MapFs -> [Ifce] -> Ctrs -> [Decl] -> Type -> ExpWhere -> ExpWhere
mapWhere fs ifces ctrs dsigs xtp (ExpWhere (z,ds,e)) = ExpWhere (z, ds', e')
  where
    e'  = mapExpr  fs ifces ctrs dsigs'' xtp e
    ds' = mapDecls fs ifces ctrs dsigs'  ds

    dsigs''   = dsigs ++ filter isDSig ds'
    dsigs'    = dsigs ++ filter isDSig ds

-------------------------------------------------------------------------------

mapPatt :: MapFs -> [Ifce] -> Ctrs -> [Decl] -> Type -> Patt -> ([Decl],Patt)
mapPatt fs@(_,_,fP) ifces ctrs dsigs xtp p = (ds', fP ifces ctrs dsigs p') where
  (ds',p') = aux p

  -- TODO: TAny
  aux (PWrite z id)    = (dsig, PWrite z id) where
                          dsig = bool [DSig z id cz xtp] [] (xtp==TAny)
  aux (PRead  z e)     = ([], PRead z $ mapExpr fs ifces ctrs dsigs TAny e) -- TODO: xtp
  aux (PTuple z ps)    = (concat ds', PTuple z ps') where
                          (ds',ps') = unzip $ map (mapPatt fs ifces ctrs dsigs TAny) ps
  aux (PCall  z p1 p2) = (ds2'++ds1', PCall z p1' p2') where
                          (ds1',p1') = mapPatt fs ifces ctrs dsigs TAny p1
                          (ds2',p2') = mapPatt fs ifces ctrs dsigs TAny p2
  aux p                = ([], p)

-------------------------------------------------------------------------------

mapExpr :: MapFs -> [Ifce] -> Ctrs -> [Decl] -> Type -> Expr -> Expr
mapExpr fs@(_,fE,_) ifces ctrs dsigs xtp e = fE ifces ctrs dsigs xtp (aux e) where
  aux (EFunc  z cs tp ups whe) = EFunc  z cs tp ups $ mapWhere fs ifces ctrs' (arg:dsigs) xtp whe where
                                  ctrs' = Ctrs $ getCtrs ctrs ++ getCtrs cs
                                  arg = DSig z "..." cz inp
                                  (inp,xtp) = case tp of
                                                TFunc inp out -> (inp,out)
                                                otherwise     -> (TAny,TAny)
  -- TODO: TAny
  aux (EData  z hr e)          = EData  z hr $ mapExpr fs ifces ctrs dsigs TAny e
  aux (ETuple z es)            = ETuple z $ map (mapExpr fs ifces ctrs dsigs TAny) es
  aux (ECall  z e1 e2)         = ECall  z e1' e2' where
                                  e1' = mapExpr fs ifces ctrs dsigs TAny e1
                                  e2' = mapExpr fs ifces ctrs dsigs TAny e2
  aux (ECase  z e l)           = ECase  z e' l' where
    e'         = mapExpr fs ifces ctrs dsigs TAny e
    (ps, ws)   = unzip l
    (dss',ps') = unzip $ map (mapPatt fs ifces ctrs dsigs xtp) ps
    ws'        = map f (zip dss' ws) where
                  f (ds,w) = mapWhere fs ifces ctrs dsigs' xtp w where
                              dsigs' = (filter isDSig ds) ++ dsigs
    l'         = zip ps' ws'
  aux e                        = e