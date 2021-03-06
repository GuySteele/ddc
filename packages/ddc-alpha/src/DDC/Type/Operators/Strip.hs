{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | Stripping fetters from types.
module DDC.Type.Operators.Strip
	( stripFWheresT
	, stripMonoFWheresT
	, stripForallContextT
	, stripToBodyT)
where
import DDC.Type.Exp
import DDC.Type.Predicates
import DDC.Type.Compounds
import DDC.Type.Pretty		()
import qualified Data.Map	as Map

-- | Strip all fetters from this type, returning just the body.
stripFWheresT  :: Type -> Type
stripFWheresT  = stripFWheresT' False


-- | Strip the monomorphic FWhere fetters (the ones with cids as the RHS) 
--	leaving the others still attached.
stripMonoFWheresT :: Type -> Type
stripMonoFWheresT = stripFWheresT' True


-- | Worker function for above
stripFWheresT' 
	:: Bool 		-- ^ whether to only stip monomorphic FWhere fetters
	-> Type			-- ^ the type to strip
	-> Type

stripFWheresT' justMono	tt
 = case tt of
	TNil		-> tt

	TError{} -> tt

	TForall b k t
	 -> TForall b k $ stripFWheresT' justMono t

	TConstrain t crs
	 -- Just take the monomorphic FWheres
	 | justMono
	 -> let	t'	= stripFWheresT' justMono t
		crs'	= Constraints
				(Map.filterWithKey (\t1 _ -> not $ isTClass t1) $ crsEq crs)
				(crsMore  crs)
				(crsOther crs)
	
	    in	makeTConstrain t' crs'
	
         -- Take all of thw FWheres
         | otherwise
	 -> let	t'	= stripFWheresT' justMono t
	    	crs'	= Constraints
				Map.empty
				(crsMore crs)
				(crsOther crs)

	    in	makeTConstrain t' crs'
	
	TSum k ts
	 -> TSum k $ map (stripFWheresT' justMono) ts

	TApp t1 t2
	 -> let	t1'	= stripFWheresT' justMono t1
	 	t2'	= stripFWheresT' justMono t2
	    in	TApp t1' t2'

	TCon _	-> tt

 	TVar{}	-> tt


-- | Strip foralls and contexts from the front of this type.
stripForallContextT :: Type -> ([(Bind, Kind)], [Kind], Type)
stripForallContextT tt
 = case tt of
	TForall BNil k1 t2	
	 -> let ( bks, ks, tBody) = stripForallContextT t2
	    in	( bks
	        , k1 : ks
		, tBody)

 	TForall b k t2	
	 -> let	(bks, ks, tBody) = stripForallContextT t2
	    in	( (b, k) : bks
	    	, ks
		, tBody)
		
	TConstrain t1 _
	 -> stripForallContextT t1

	_		
	 -> ([], [], tt)


-- | Strip TForalls and TFetters from a type to get the body.
stripToBodyT :: Type -> Type
stripToBodyT tt
 = case tt of
 	TForall  _ _ t		-> stripToBodyT t
	TConstrain t _		-> stripToBodyT t
	_			-> tt
