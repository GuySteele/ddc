
-- For :> constraints on variables that are not to the left of an arrow,
-- eg:
--
--	fun :: forall !e1. a -(!e1)> b :- !e1 :> !Console
--
-- We can safely strengthen these to = constraints, that is:
--
--	fun :: a -(!e1)> b :- !e1 = !Console.
--
-- Later, when converting this to the core language, we can flatten the above and
-- write just:
--
--	fun :: a -(!Console)> b
--
-- Note that the quantifier for !e1 is gone, which means we don't have to pass
--	an effect parameter when calling this function in the core language.
--
-- TODO: Do the parameter var slurping in the strengthen fun directly.
--	 Pass in quantified vars directly, and demonadify this function.
--
module Type.Strengthen
	( strengthenT
	, slurpParamClassVarsT)
where
import Util
import DDC.Solve.State
import DDC.Main.Error
import DDC.Type
import qualified Data.Map	as Map
import qualified Data.Set	as Set

stage	= "Type.Strengthen"

-- | Strengthen constraints that don't constrain variables in this set.
strengthenT 
	:: Set Type 		-- ^ cids and vars that appear in parameter positions, 
				--	that is, on the left of an arrow. Constraints on
				--	these can't be strengthened.
	-> Type 		-- ^ the type to strengthen
	-> SquidM Type		-- ^ the strengthened type

strengthenT tsParam tt
 = case tt of
	TConstrain tBody crs@(Constraints crsEq crsMore crsOther)
	 -> do	(crsEq', mcrsMore)	
				<- mapAccumLM (strengthenFs tsParam) crsEq 
				$  Map.toList crsMore

		let crsMore'	= Map.fromList $ catMaybes mcrsMore
		let crs' 	= Constraints crsEq' crsMore' crsOther
		return	$ addConstraints crs' tBody

	t -> return t

strengthenFs
	:: Set Type				-- ^ cids and vars that appear in parameter positions
	-> Map Type Type			-- ^ equality constraints
	-> (Type, Type)				-- ^ more than constraints
	-> SquidM ( Map Type Type		-- new equality constraint set
	   	  , Maybe (Type, Type)	)	-- new more constraint (if any)

strengthenFs tsParam fsEq fMore
 = case fMore of
 	(t1@(TVar k (UClass cid)), t2)
	 -> do	quantVars	<- getsRef stateQuantifiedVars
	 	v		<- getCanonicalNameOfClass cid

		let result
			-- can't convert vars that have been quantified.
			| Set.member v quantVars 
			= (fsEq, Just fMore)
			
			-- can't convert vars that appear in parameter positions
			| Set.member t1 tsParam
			= (fsEq, Just fMore)
			
			| otherwise
			= (Map.insert t1 t2 fsEq, Nothing)
			
		return result
			
	_ -> return (fsEq, Just fMore)


-- | Slurp out cids and vars that appear in a parameter position in this
--	type (on the left of an arrow)
--
--   BUGS: This is wrong, but we don't test for it yet.
--	   We really need to inspect the definition of data types to determine
--	   which positions correspond to parameters.
--
slurpParamClassVarsT :: Type -> [Type]
slurpParamClassVarsT tt
 = case tt of
	TForall b k t		-> slurpParamClassVarsT t
	TConstrain t crs 	-> slurpParamClassVarsT t

	TApp t1 t2
	  | Just (t11, t12, eff, clo)	<- takeTFun tt
	  -> (Set.toList $ freeTClassVars t11) 
	     ++ slurpParamClassVarsT t12
	
	  | Just _	<- takeTData tt
	  -> []
	
	  | otherwise
	  -> slurpParamClassVarsT t1 ++ slurpParamClassVarsT t2
	
	
	TSum _ ts	-> concat $ map slurpParamClassVarsT ts
	TVar{}		-> []
	TCon{}		-> []
	TError{}	-> []	
	_		-> panic stage
			$ "slurpParamClassVarsT: no match for " % tt

