module Dyn.AST where

import qualified Data.List as L

data Ann = Ann { pos :: (Int,Int) }
  deriving (Eq, Show)

az = Ann { pos=(0,0) }

type Type = ()

type ID_Var  = String
type ID_Data = String
type ID_Hier = [ID_Data]

data Expr
  = EError Ann
  | EVar   Ann ID_Var               -- (id)         -- a ; xs
  | EUnit  Ann                      -- ()           -- ()
  | ECons  Ann ID_Hier              -- (ids)        -- Bool.True ; Int.1 ; Tree.Node
  | ETuple Ann [Expr]               -- (exprs)      -- (1,2) ; ((1,2),3) ; ((),()) // (len >= 2)
  | EFunc  Ann Type Expr            -- (type,body)
  | ECall  Ann Expr Expr            -- (func,arg)   -- f a ; f(a) ; f(1,2)
  | EArg   Ann
  | EIf    Ann Expr Expr Expr Expr  -- (p,e,t,f)    -- if 10 matches x then t else f
  deriving (Eq, Show)

newtype Where = Where (Expr,[Dcl])
newtype Dcl   = Dcl   (ID_Var, Type, Where)

type Prog  = Where

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

exprToString :: Expr -> String
exprToString (EError _)           = "error"
exprToString (EVar   _ id)        = id
exprToString (EUnit  _)           = "()"
exprToString (ECons  _ ["Int",n]) = n
exprToString (ECons  _ hier)      = L.intercalate "." hier
exprToString (EArg   _)           = "..."
exprToString (ETuple _ es)        = "(" ++ L.intercalate "," (map exprToString es) ++ ")"
exprToString (EFunc  _ () e)      = "func () " ++ exprToString e
exprToString (ECall  _ e1 e2)     = "(" ++ exprToString e1 ++ " " ++ exprToString e2 ++ ")"
exprToString (EIf    _ p e t f)   = "if " ++ exprToString p ++ " matches " ++ exprToString e
                                      ++ " then " ++ exprToString t
                                      ++ " else " ++ exprToString f
--exprToString e                    = error $ show e

-------------------------------------------------------------------------------

dclToString :: Dcl -> String

dclToString (Dcl (id, (), w)) = id ++ " :: () = " ++ whereToString w

-------------------------------------------------------------------------------

whereToString :: Where -> String

whereToString (Where (e,[]))   = exprToString e
whereToString (Where (e,dcls)) = exprToString e ++ " where " ++
                                  L.intercalate "," (map dclToString dcls)
