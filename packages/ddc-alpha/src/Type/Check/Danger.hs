 
module Type.Check.Danger
	(dangerousCidsT)
where
import Util
import DDC.Main.Error
import DDC.Var
import DDC.Type
import DDC.Var.PrimId		as Var
import qualified Data.Set	as Set
import qualified Data.Map	as Map

stage	= "Type.Check.Danger"

dangerousCidsT :: Type -> [ClassId]
dangerousCidsT tt
 = let	tsDanger	= dangerT Set.empty Map.empty tt
   in	[ cid	| TVar k (UClass cid)	<- Set.toList tsDanger
	    		, elem k [kValue, kEffect, kClosure] ]
	    
dangerT 
	:: Set Type
	-> Map Type Type
	-> Type -> Set Type

dangerT rsMutable fsClosure tt
 = case tt of
 	TVar{}			-> Set.empty
	TCon{}			-> Set.empty

	TForall b k t		
	 -> dangerT rsMutable fsClosure t

	-- fetters
	TConstrain t1 crs
	 ->     -- remember any regions flagged as mutable
	    let	fs		= fettersOfConstraints crs
		rsMoreMutable	= Set.fromList
	 			$ [r	| FConstraint v [r]	<- fs
					, varId v 	== (VarIdPrim Var.FMutable) ]

		rsMutable'	= Set.union rsMutable rsMoreMutable

		-- collect up more closure bindings
		fsClosure'	= Map.union 
					fsClosure 
					(Map.fromList [(u1, u2) | FWhere u1 u2	<- fs
								, kindOfType u1 == kClosure])

		-- decend into type and fetters
		t1Danger	= dangerT rsMutable' fsClosure' t1

	    in	t1Danger
	    	    
	TApp{}
	 | Just (t1, t2, eff, clo)	<- takeTFun tt
	 -> let cloDanger	
	 		| TSum kC [] <- clo
			, kC	== kClosure
			= Set.empty

			| otherwise
			= case Map.lookup clo fsClosure of
				Just c	-> dangerT rsMutable fsClosure c
				Nothing	-> Set.empty
			
	    in	Set.unions
			[ cloDanger ]

   	 | Just (v, k, ts)		<- takeTData tt
	 -> dangerT_data rsMutable fsClosure (v, k, ts)

	 | Just (v, t)		<- takeTFree tt
	 -> dangerT rsMutable fsClosure t
	 
	 | Just (t1, t2)	<- takeTDanger tt
	 -> if Set.member t1 rsMutable
		then freeTClassVars t2
		else dangerT rsMutable fsClosure t2
	
	 | otherwise
	 -> Set.empty

	TSum kC ts
	 | kC	== kClosure
	 -> Set.unions $ map (dangerT rsMutable fsClosure) ts


	-- effects
	TSum kE ts
	 | kE	== kEffect	-> Set.empty

	-- skip over errors
	TError{}		-> Set.empty
	 
	_ -> panic stage
		$ "dangerT: no match for " % tt
	 

dangerT_data rsMutable fsClosure (v, k, ts)
	-- if this ctor has any mutable regions then all vars from this point down are dangerous
 	| or $ map 	(\t -> case t of 
 				TVar{}		-> Set.member t rsMutable
				_		-> False)
			ts

	= Set.unions $ map freeTClassVars ts

	 -- check for dangerous vars in subterms
	| otherwise
 	= Set.unions $ map (dangerT rsMutable fsClosure) ts
