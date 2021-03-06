{-# OPTIONS -fwarn-incomplete-patterns #-}

-- | Take sets of free variables by core expressions.
module Core.Plate.FreeVars
	( freeVars
	, varsBoundByG
	, varsBoundByW )
where
import DDC.Core.Exp
import DDC.Type
import DDC.Var
import DDC.Util.FreeVars
import Data.Set			((\\), unions, fromList, empty, singleton)
import Util			hiding ((\\))
import qualified Data.Set 	as Set
import qualified Shared.VarUtil	as Var

 
-- Exp ---------------------------------------------------------------------------------------------
instance FreeVars Exp where
 freeVars xx
  = case xx of
	XNil		-> empty
	
 	XVar	v t
 	 | Var.isCtorName v -> empty
	 | otherwise
	 -> unions
	 	[ singleton v
		, freeVars t ]

	XPrim _ t	-> freeVars t

	XLAM b k e
	 -> let Just v	= takeVarOfBind b
	    in  unions 	[ freeVars k
			, freeVars e ]
			\\ Set.singleton v

	XAPP x t
	 -> unions
	 	[ freeVars x
		, freeVars t ]

	XLam v t e eff clo	
	 -> unions
	 	[ freeVars t
		, freeVars e ]
		\\ fromList [v]

	XApp x1 x2
	 -> unions
	 	[ freeVars x1
		, freeVars x2 ]

	XTau t x
	 -> unions
	 	[ freeVars t
		, freeVars x ]

	XLocal v vs x
	 -> freeVars x \\ fromList [v]

	XDo xs
	 -> let
	 	bound	= unions
			$ map boundByS xs
			
		free	= unions
			 $ map freeVars xs

	    in free \\ bound
		
	XMatch aa
	 -> unions $ map freeVars aa
		
	XLit{}
	 -> empty
	



boundByS ::	Stmt	-> Set Var
boundByS	x
 = case x of
 	SBind v e
	 -> let
	    in	unions	[ fromList (maybeToList v) ]


-- Prim --------------------------------------------------------------------------------------------
instance FreeVars Prim where
 freeVars m	= empty


-- Stmt --------------------------------------------------------------------------------------------
instance FreeVars Stmt where
 freeVars xx
  = case xx of
 	SBind v x
	 -> unions 
	 	[ freeVars x ]
		\\ fromList (maybeToList v)


-- Alt  --------------------------------------------------------------------------------------------
instance FreeVars Alt where
 freeVars aa	
  = case aa of
 	AAlt gs x
	 -> let
	 	bound	= unions 
			$ map varsBoundByG gs
			
		free	= unions 
		 	[ unions $ map freeVars gs
			, freeVars x ]
	    in	free \\ bound
				

varsBoundByG ::	Guard -> Set Var
varsBoundByG	g
 = case g of
	GExp  w x	-> varsBoundByW w


-- Guard -------------------------------------------------------------------------------------------
instance FreeVars Guard where
 freeVars gg
  = case gg of
	GExp  w x
	 -> (Set.union (freeVars x) (freeVars w))
	 	\\ varsBoundByW w

varsBoundByW ::	Pat	-> Set Var
varsBoundByW	ww
 = case ww of
	WVar v		-> Set.singleton v
 	WLit{}	 	-> empty
	WCon sp v fs	-> fromList $ map t3_2 fs
	

-- Pat ---------------------------------------------------------------------------------------------
instance FreeVars Pat where
 freeVars pp
  = case pp of
	WVar v		-> empty
  	WLit sp c	-> empty
	WCon sp v lts	-> Set.unions $ map (freeVars . t3_3) lts

		
		
