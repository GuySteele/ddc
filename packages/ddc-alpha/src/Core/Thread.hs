-- | Thread witness variables through the program to replace statically constructed
--	witnesses in type applications.
--
--   Static witness applications are things like:
--	f %r1 (Const %r1)
--
--   	In this application (Const %r1) satisfies the constraint, but it's not
--	syntactically sound. We might also use (Mutable %r1) somewhere else in the
--	program.
--	
module Core.Thread 
	(threadGlob)
where
import Core.Plate.Trans
import DDC.Main.Error
import DDC.Core.Exp
import DDC.Core.Glob
import DDC.Type
import DDC.Var
import Util
import qualified DDC.Var.PrimId		as Var
import qualified Data.Map		as Map

stage		= "Core.Thread"

-- | Thread witness variables in this tree
threadGlob 
	:: Glob		-- ^ Header glob
	-> Glob		-- ^ Module glob
	-> Glob

threadGlob cgHeader cgModule
	= evalState (threadGlobM cgHeader cgModule) []
		

threadGlobM :: Glob -> Glob -> ThreadM Glob
threadGlobM cgHeader cgModule
 = do	
	-- Add all the top level region witnesses to the state.
	mapM_ 	(\(PRegion r vts) -> mapM addRegionWitness vts) 
		$ Map.elems 
		$ globRegion cgModule
			
	let transTable
		 = transTableId
		 { transX 	= thread_transX
		 , transX_enter	= thread_transX_enter }

	mapBindsOfGlobM (transZM transTable) cgModule


addRegionWitness :: (Var, Type) -> ThreadM ()
addRegionWitness (v, t)
 = do	let k	= kindOfType t
	pushWitnessVK v k
	return ()


-- | bottom-up: replace applications of static witnesses with bound witness variables.
thread_transX :: Exp -> ThreadM Exp
thread_transX xx
	| XAPP x t		<- xx
	, Just _		<- takeTWitness t
	= do	t'	<- rewriteWitness t
	 	return	$ XAPP x t'

	-- pop lambda bound witnesses on the way back up because we're leaving their scope.
	| XLAM b k x		<- xx
	= do	let Just v	= takeVarOfBind b
		popWitnessVK v k
	 	return	xx

	-- pop locally bound witnesses on the way back up because we're leaving their scope.
	| XLocal r vts x	<- xx
	= do	mapM_ (\(v, k) -> popWitnessVK v k)
	 		[ (v, kindOfType t)	
				| (v, t) <- reverse vts]
		
	 	return xx

	| otherwise
	= return xx


thread_transX_enter :: Exp -> ThreadM Exp
thread_transX_enter xx
 = case xx of
 	XLAM b k x
	 -> do	let Just v	= takeVarOfBind b
		pushWitnessVK v k
	 	return	xx

	XLocal r vts x
	 -> do	mapM_ (\(v, k) -> pushWitnessVK v k)
	 		[ (v, kindOfType t)	
				| (v, t) <- vts]

 		return xx

	_ 	-> return xx		


-- | If this is an explicitly constructed witness then try and replace it by
--	a variable which binds the correct one.
rewriteWitness 
	:: Type 
	-> ThreadM Type

rewriteWitness tt
 = case tt of
	-- handle compound witnesses
	TSum k@(KSum{}) ts
	 -> do	ts'	<- mapM rewriteWitness' ts
		return	$ TSum k ts'

	_	-> rewriteWitness' tt

rewriteWitness' tt
 
	-- Got an application of an explicit witness to some region.
	--	Lookup the appropriate witness from the environment and use
	--	that here.
	| Just (tcWitness, _, [TVar k (UVar vT)]) 	<- mClass
	= do	let Just kcWitness	= takeKiConOfTyConWitness tcWitness
		Just vW			<- lookupWitness kcWitness vT
		let k			= kindOfType tt
		return $ TVar k $ UVar vW

	-- purity of no effects is trivial
	| Just (TyConWitnessMkPure, _, [TSum kE []])	<- mClass
	, kE	== kEffect
	= return tt

	-- empty of no closure is trivial
	| Just (TyConWitnessMkEmpty, _, [TSum kC []]) 	<- mClass
	, kC	== kClosure
	= return tt

	-- build a witness for purity of this effect
	| Just (TyConWitnessMkPure, _, [eff])		<- mClass
	= do	w	<- buildPureWitness eff
		return	$ w

	-- leave shape witnesses for Core.Reconstruct to worry about
	| Just (TyConWitnessMkVar vC, _, _)		<- mClass
	, VarIdPrim Var.FShape{}			<- varId vC
	= return tt

	-- leave user type classes for Core.Dict to worry about
	| Just (TyConWitnessMkVar vC, _, _)		<- mClass
	= return tt

	-- function types are always assumed to be lazy, 
	--	Lazy witnesses on them are trivially satisfied.
	| Just (TyConWitnessMkHeadLazy, _, [t1])		<- mClass
	, isJust (takeTFun t1)
	= return tt

	| Just (TyConWitnessMkHeadLazy, _, [TConstrain t1 _]) <- mClass
	, isJust (takeTFun t1)
	= return tt
	
	-- some other witness we don't handle
	| Just (vC, _, ts)		<- mClass
	= panic stage
		("thread_transX: can't find a witness for " % mClass % "\n")

	-- some other type
	| otherwise
	= return tt

	where	mClass	= takeTWitness tt


-- | Build a witness that this effect is pure.
buildPureWitness
	:: Effect
	-> ThreadM Witness

buildPureWitness eff@(TApp t1 tR@(TVar kR (UVar vR)))
	| t1 == tRead
	, kR == kRegion
	= do	
		-- try and find a witness for constness of the region
		Just wConst	<- lookupWitness KiConConst vR
		let  k		= KApp kConst tR

		-- the purity witness gives us purity of read effects on that const region
		return		$ TApp (TApp tMkPurify tR) (TVar k $ UVar wConst)

buildPureWitness eff@(TSum kE _)
 	| kE	== kEffect
 	= do	let effs	= flattenTSum eff
 		ts		<- mapM buildPureWitness effs
		let ks		= map kindOfType ts
		return		$ makeTSum (makeKSum ks) ts

buildPureWitness eff@(TVar kE (UVar vE))
 	| kE	== kEffect
 	= do	Just w	<- lookupWitness KiConPure vE
 		return (TVar (KApp kPure eff) $ UVar w)

buildPureWitness eff
 = panic stage
 	$ "buildPureWitness: Cannot build a witness for purity of " % eff % "\n"


-- State ------------------------------------------------------------------------------------------
-- Stack of what witneses are currently in scope.
type ThreadS	
	= [ ( (KiCon, Var) 	-- witness kind constructor, TREC var
	    , Var)]		-- type vars that binds the corresponding witness.

-- Rewriter monad.
type ThreadM 	= State ThreadS


-- Inspect this kind. If it binds a witness then push it onto the stack.
pushWitnessVK :: Var -> Kind -> ThreadM ()
pushWitnessVK vWitness k
 	| KApp (KCon kcWitness _) (TVar kV (UVar vT))	<- k
	, elem kV [kRegion, kEffect, kValue, kClosure]
	= modify $ \s -> ((kcWitness, vT), vWitness) : s
	| otherwise
	= return ()


-- Inspect this kind. If it binds a witness then pop it from the stack.
popWitnessVK :: Var -> Kind -> ThreadM ()
popWitnessVK vWitness k
	| KApp (KCon kcWitness _) (TVar kV (UVar vRE)) <- k
	= do
		state	<- get
		let (xx	:: ThreadM ())
			| (c : cs)			<- state
			, c == ((kcWitness, vRE), vWitness)
			= put cs
			
			| otherwise
			= panic stage
			$ "popWitnessVK: witness to be popped does not match.\n"			
		xx

	| otherwise
	= return ()


-- | Try to find a witness of the given kind in the current environment.
lookupWitness 
	:: KiCon
	-> Var 	
	-> ThreadM (Maybe Var)
	
lookupWitness kCon vArg
 = do	state	<- get
	let mvWitness
		-- we've got a witness for this class in the table.
		| Just vWitness	<- lookup (kCon, vArg) state
		= Just vWitness

		-- uh oh, we don't have a witness for this one.
		-- Print an error instead of panicing so we can still drop the file for	-dump-core-thread
		-- Core.Reconstruct will catch this problem in a subsequent stage.
	 	| otherwise
	 	= freakout stage
			("thread_transX: can't find a witness of kind " % kCon %% vArg % "\n"
			 % "state = " % state % "\n\n")
			$ Nothing

	return mvWitness
	
