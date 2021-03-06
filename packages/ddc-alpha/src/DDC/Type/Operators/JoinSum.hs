{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | Joining the manifest effect and closure portions of a type.
--   This is used when we choose between two functions of differing effects, 
--   for example, in @if .. then putStr else id@. Although the value and region
--   portions of both types must be the same, we can sum the effect and closure
--   portions to mirror what happens during source-level type inference.
--
--   NOTE: because we only strengthen constraints who's var does
--   not appear as a parameter, we don't end up trying to join two types like:
--
--   @
-- 	t1: (a -(!e1)>   b) -> c :- !e1 :> !EFF2
--	t2: (a -(!EFF1)  b) -> c	
--   @
--  
--   To join effects in parameters we would have to use something like:
--
--   @
-- 	t1 `joinMax` t2
--	  = (a -(!e1)> b) -> c 
--	  :- !e1 :> !EFF1 \/ !EFF2
--   @	
-- 
--   This would mean we'd have to extend the !e1 constraint in the 
--   environment, but it's not needed at the moment.
--
module DDC.Type.Operators.JoinSum
	(joinSumTs)
where
import DDC.Main.Error
import DDC.Type.Exp
import DDC.Type.Compounds
import DDC.Type.Kind
import DDC.Type.Pretty		()
import DDC.Main.Pretty
import Control.Monad

stage	= "DDC.Type.JoinSum"

-- | Join all these types.
--	The value and region portions must be the same.
--	The effect and closure portions are summed.
joinSumTs :: [Type] -> Maybe Type
joinSumTs []	= Nothing
joinSumTs (t:ts)	= foldM joinTT t ts


joinTT :: Type -> Type -> Maybe Type


-- Flip the args around to put the easy-to-unify argument first.
--	this means that the code for joinTT_work can get by with less cases.
joinTT t1 t2
	| TVar{}		<- t2
	= joinTT_work t2 t1

	| otherwise
	= joinTT_work t1 t2

joinTT_work t1 t2
	| Just (t11, t12, e1, c1) <- takeTFun t1
	, Just (t21, t22, e2, c2) <- takeTFun t2
	, t11 == t21
	, Just tY		<- joinTT t12 t22
	, Just eff		<- joinTT e1 e2
	, Just clo		<- joinTT c1 c2
	= Just $ makeTFun t11 tY eff clo

	| TApp tX1 tY1		<- t1
	, TApp tX2 tY2		<- t2
	, Just tX		<- joinTT tX1 tX2
	, Just tY		<- joinTT tY1 tY2
	= Just $ TApp tX tY

	| TVar k1 (UVar v1)		<- t1
	, TVar _ (UVar v2)		<- t2
	, v1 == v2	
	= Just $ TVar k1 $ UVar v1

	| TVar k1 (UMore v1 b1)	<- t1
	, TVar _  (UMore v2 _)	<- t2
	, v1 == v2
	= Just $ TVar k1 $ UMore v1 b1

	| TCon c1		<- t1
	, TCon c2		<- t2
	, c1 == c2	
	= Just $ TCon c1

	| TVar k1 _		<- t1
	, k2			<- kindOfType t2
	, isEffClo k1 k2	
	= Just $ makeTSum k1 [t1, t2]

	| TVar k1 (UMore _ _) <- t1
	, k2			<- kindOfType t2
	, isEffClo k1 k2
	= Just $ makeTSum k1 [t1, t2]

	| TSum k1 ts1		<- t1
	, k2 			<- kindOfType t2
	, isEffClo k1 k2
	= Just $ makeTSum k1 (t2 : ts1)

	| TSum k2 ts2		<- t2
	, k1			<- kindOfType t1
	, isEffClo k1 k2
	= Just $ makeTSum k2 (t2 : ts2)
	
	| otherwise
	= panic stage 
	$ vcat	[ ppr "joinTT: cannot join\n"
		, "t1:  " % t1 	% "\n"
		, "t2:  " % t2 ]


isEffClo k1 k2
	=  (isEffectKind  k1 && isEffectKind  k2) 
	|| (isClosureKind k1 && isClosureKind k2)


