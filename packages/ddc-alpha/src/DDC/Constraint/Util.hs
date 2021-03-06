{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | Bits and pieces for dealing with type constraints.
module DDC.Constraint.Util
	( isCTreeNil
	, isCBranch
	, isCEq
	, isCMore
	, isCProject
	, isCGen
	, makeCBranch
	, makeCEqs
	, takeCBindVs
	, mergeCBinds
	, slurpContains)
where
import DDC.Constraint.Exp
import DDC.Solve.Location
import DDC.Type
import DDC.Var
import DDC.Main.Error
import Util
import qualified Data.Map	as Map
import qualified Data.Set	as Set

stage	= "DDC.Constraint.Util"

-- Predicates -----------------------------------------------------------------
isCTreeNil :: CTree -> Bool
isCTreeNil b
 = case b of
	CTreeNil	-> True
	_		-> False
	

isCBranch :: CTree -> Bool
isCBranch b
 = case b of
 	CBranch{}	-> True
	_		-> False

isCEq :: CTree -> Bool
isCEq b
 = case b of
	CEq{}		-> True
	_		-> False

isCMore :: CTree -> Bool
isCMore b
 = case b of
	CMore{}		-> True
	_		-> False

isCProject :: CTree -> Bool
isCProject b
 = case b of
	CProject{}	-> True
	_		-> False

isCGen :: CTree -> Bool
isCGen b
 = case b of
	CGen{}		-> True
	_		-> False
	


makeCBranch :: CBind -> [CTree] -> CTree
makeCBranch bind cs
	| null cs
	= CTreeNil

	| BNothing	 <- bind
	, [cc@CBranch{}] <- cs
	= cc

	| otherwise
	= CBranch bind $ filter (not . isCTreeNil) cs
	

-- | For some types [t1, t2, t3 ...] make constraints t1 = t2, t1 = t2, t1 = t3 ...
--   The first type must be a TVar else panic.
makeCEqs :: TypeSource -> [Type] -> [CTree]
makeCEqs src tt
 = case tt of
	t1@TVar{}: tsRest	-> [CEq src t1 t | t <- tsRest]
	_			-> panic stage $ "makeCEqs: no match"

	
-- | Take all the variables bound by term that this constraint branch is of.
takeCBindVs :: CBind -> [Var]
takeCBindVs cc
 = case cc of
	BNothing	-> []
	BLet    vs	-> vs
 	BLetGroup  vs	-> vs

	BLambda vs	-> vs
	BDecon  vs	-> vs


-- | Merge the variables in two similar CBinds into another.
mergeCBinds :: CBind -> CBind -> CBind
mergeCBinds (BLet    	vs1) (BLet    	vs2)	= BLet	  	(vs1 ++ vs2)
mergeCBinds (BLetGroup  vs1) (BLetGroup vs2) 	= BLetGroup  	(vs1 ++ vs2)
mergeCBinds (BLambda 	vs1) (BLambda 	vs2)	= BLambda 	(vs1 ++ vs2)
mergeCBinds (BDecon  	vs1) (BDecon  	vs2) 	= BDecon  	(vs1 ++ vs2)
mergeCBinds _ _					= panic stage $ "mergeCBinds: no match"

-- | Slurp the containment map from this tree.
--	This is a map of all the variables bound by sub-branches in this tree.
--
--	TODO: A more efficient implementation, not using catMap.
--
slurpContains :: CTree -> Map CBind (Set CBind)
slurpContains tree
	= Map.fromList 
	$ map (\(v, vs) -> (v, Set.fromList vs))
	$ collate
	$ slurpContains' Nothing tree


slurpContains' :: Maybe CBind -> CTree -> [ (CBind, CBind) ]
slurpContains' mParent tree@(CBranch{})

	| BNothing		<- boundVsT 
	= catMap (slurpContains' mParent) (branchSub tree)

 	| Nothing		<- mParent
	= catMap (slurpContains' (Just boundVsT)) (branchSub tree)
	
	| Just parent		<- mParent
	= (parent, boundVsT) 
	: catMap (slurpContains' (Just boundVsT)) (branchSub tree)
	
	where	boundVsT	= branchBind tree

slurpContains' _ _
	= []
	