{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
-- | All regions are assumed constant until proven mutable.
--	This means that we can generalise type variables in scheme but find
--	out they were actually are dangerous and non-generalisable later on.
--
--      If we were to instantiate these wrongly-generalised vars more than once
--      then they could potentially end up with diffent types, which makes
--      the type system unsound.
--
--      It would be better to do some back-tracking to recover from this, but
--      instead we just check for wrongly generalised type vars each time we do an
--	instantiation and report an error asking for a type sig if there are problems.
--
--      Type sigs are added to the graph before anything else, so we'll see the mutability
--      constraints during generaliation on the next time around.
-- 
module DDC.Solve.Check.Late
	( checkSchemes
	, checkSchemeDangerCid
	, checkSchemeDanger)
where
import Shared.VarPrim
import Util
import DDC.Solve.Location
import DDC.Solve.Error
import DDC.Solve.State
import DDC.Solve.Trace
import DDC.Main.Error
import DDC.Type
import DDC.Var
import qualified Data.Map	as Map
import qualified Data.Sequence	as Seq

stage	= "DDC.Solve.Check.Late"
debug	= False
trace s	= when debug $ traceM s


-- | Check all schemes in the graph.
checkSchemes :: SquidM ()
checkSchemes 
 = do	trace	$ ppr $ "*    checkSchemes\n"
	errs	<- foldClasses checkSchemeDanger []
	addErrors errs
	trace	$ ppr $ "*    done checking schemes\n"


-- | Check for wrongly generalised dangerous type variables in the scheme in this class.
checkSchemeDangerCid :: ClassId -> SquidM [Error]
checkSchemeDangerCid cid
 = do	Just c	<- lookupClass cid
 	checkSchemeDanger [] c

 
-- Check that the regions above quantified dangerous vars haven't become mutable.
checkSchemeDanger :: [Error] -> Class -> SquidM [Error]
checkSchemeDanger errs c
	| Class { classUnified	= Just node }	<- c
	, NScheme t 	<- node
	= do	trace 	$ "*   checkSchemeDanger\n"
			% "    t = " % t % "\n"

		let clo	= trimClosureC
			$ makeTFreeBot (varWithName "foo") t
		
		let ds	= catMaybes
			$ map (\d -> case d of
					TApp{}
					 | Just (_, t2)		<- takeTFree d
					 , Just (t11, t12)	<- takeTDanger t2
					 -> Just (t11, t12)
					
					_			-> Nothing)
			$ flattenTSum clo
		
		trace	$ "    clo  = " % clo 	% "\n"
			% "    ds   = " % ds	% "\n"
			
		moreErrs	
			<- liftM catMaybes
			$ mapM (checkDanger c) ds
			
		trace	$ "    errs  = " % errs	% "\n\n"
		return (errs ++ moreErrs)

	| otherwise
	= return errs
 
	
-- | Produce an error if the region is mutable
checkDanger :: Class -> (Type, Type) -> SquidM (Maybe Error)
checkDanger (Class 
		{ classId 	= cidScheme })
		( tRegion@(TVar kR (UClass cidR))
		, t2)

	| kR == kRegion
	, TVar _ (UVar varT)	<- t2
	= do 	mfMutableSrc	<- lookupMutable cidR
		case mfMutableSrc of
	 	 Nothing	-> return Nothing
	 	 Just (fMutable, srcMutable)
	  	  -> do
			varScheme	<- getDisplayNameOfClass cidScheme
			Just tNode	<- takeShallowTypeOfCidAsSquid cidScheme
			return	$ Just
				$ ErrorLateConstraint
					{ eScheme 		= (varScheme, tNode)
					, eMutableRegion	= tRegion
					, eMutableFetter	= fMutable
					, eMutableSrc		= srcMutable
					, eDangerVar		= varT }

	-- var is monomorphic, ok
	| kR	== kRegion
	, TVar _ UClass{}	<- t2
	= 	return Nothing
	
checkDanger _ (t1, t2)
 = panic stage
	$ "checkDanger: no match\n"
	% "    t1 = " % t1	% "\n"
	% "    t2 = " % t2	% "\n"
	% "\n"
	
	
-- | See if there is a Mutable fetter in this class
lookupMutable 
	:: ClassId 
	-> SquidM (Maybe (Fetter, TypeSource))

lookupMutable cid
 = do	Just cls  	<- lookupClass cid
	let fetters	=  classFetters cls
	
	case Map.lookup primMutable fetters of
	 Just srcs	
	  -> do	let (src Seq.:< _) = Seq.viewl srcs
		return $ Just 
			( FConstraint primMutable [TVar (classKind cls) $ UClass cid]
			, src)
		
	 Nothing
	  ->	return Nothing

