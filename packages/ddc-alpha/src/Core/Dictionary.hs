
-- | Resolve calls to overloaded functions.
module Core.Dictionary
	(dictGlob)
where
import Core.Dictionary.InfoOverloaded
import Core.Dictionary.Env
import Core.Util.Bits
import Core.Plate.Trans
import Util
import DDC.Main.Error
import DDC.Main.Pretty
import DDC.Core.Glob
import DDC.Core.Exp
import DDC.Type
import DDC.Var
import qualified Data.Sequence		as Seq
import qualified Data.Map		as Map
import qualified Data.Foldable		as Foldable
import qualified Debug.Trace

stage		= "DDC.Core.Dictionary"
debug		= False
trace ss x	= if debug then Debug.Trace.trace (pprStrPlain ss) x else x

-- | The RHS of every instance function must be the var of a top level function.
dictGlob 
	:: Glob		-- ^ Header module.
	-> Glob 	-- ^ Source module.
	-> Glob
	
dictGlob cgHeader cgModule
 = let	env	= Env
		{ envHeaderGlob	= cgHeader
		, envModuleGlob	= cgModule }

   in	mapBindsOfGlob 
		(transformS (rewriteS env)) 
		cgModule
   	
	
-- | Rewrite applcations of overloaded functions in this statement.
rewriteS :: Env -> Stmt -> Stmt
rewriteS env ss
 = case ss of
 	SBind mV x		-> SBind mV $ rewriteX env x


-- Look for applications that might be of overloaded functions.	
rewriteX :: Env -> Exp -> Exp
rewriteX env xx
 = case xx of
	XTau t x		-> XTau t (rewriteX env x)

	-- Value applications might be of overloaded functions.
	XApp{}			-> rewriteAppX env xx

	-- Literals aren't overloaded functions.
	XAPP XLit{} _		-> xx

	-- Type applications might be of overloaded functions.
	XAPP{}			-> rewriteAppX env xx

	_			-> xx
	

-- | If this appliction is of an overloaded function then rewrite the application
--	so it applies the appropritate instance function directly.
--
--   The expression to rewrite must be some application of a value variable.
--
rewriteAppX :: Env -> Exp -> Exp
rewriteAppX env xx
 	-- Flatten the application expression so we can get at the var of 
	--	the function being applied.
	| (Left (XVar vOverloaded tOverloaded) : xsArgs)
		<- flattenApps xx
	
	-- See if the var being applied is defined in one of the type class
	--	declarations. If it is then we have to rewrite the application.
	, Just	infoOverloaded	<- lookupOverloadedVar env vOverloaded
	= let	
		-- Get the forall bound vars that are out the front of the type scheme
		--	for the overloaded variable.
		(bksDecl, _tBodyDecl)	= takeTForall $ infoOverloadedType infoOverloaded
		Just vsDeclQuantVars	= sequence $ map (takeVarOfBind . fst) bksDecl

		-- Get the type arguments from the application. 
		--	There should be the same number of type args as quantified
		--	variables in the type scheme of the overloaded variable.
		tsUseTypeArgs
			= [ t	| Right t <- take (length vsDeclQuantVars) xsArgs]
				
		-- Next comes witness arguments.
		--	These should get subsumed into the above when we refactor
		--	TContext to TForall
		tsUseTypeArgsWitness
			= [t	| Right t <- drop (length vsDeclQuantVars) xsArgs]
			
		-- Last come the the value argments.
		xsValueArgs
			= drop (length tsUseTypeArgs + length tsUseTypeArgsWitness) xsArgs 
			
		-- Build a map of how each of the quantified type variables is instantiated.
		vtsInstantiations
			= Map.fromList $ zip vsDeclQuantVars tsUseTypeArgs
			
		-- Get the parameter list of parameter types that matching instances should have.
		Just (tsInstanceArgs :: [Type])
			= sequence
			$ map (liftM flattenT)
			$ map (\v -> Map.lookup v vtsInstantiations)
			$ map fst
			$ infoOverloadedClassParams infoOverloaded

		-- Try and find matching instances.
		vClass	= infoOverloadedClassName infoOverloaded
		psMatchingInstances
			= Foldable.toList 
			$ Seq.filter
				(\p@PClassInst{}
				  -> instanceMatchesArgs 
					( vClass
					, tsInstanceArgs)
					( topClassInstName p
					, topClassInstArgs p))
				$ infoInstances infoOverloaded

	  in case psMatchingInstances of
		[]	-> panic stage
			$  vcat [ ppr "Cannot find matching instance for overloaded application."
				, ppr $ "with expression: "     % xx 
				, ppr $ "class name:      "     % vClass
				, ppr $ "class type args: "	% tsInstanceArgs ]

		x:y:_ 	-> panic stage
			$ vcat	[ ppr "Overlapping instances."
				, ppr $ "with expression: " 	% xx
				, ppr $ "instances:\n"		%> psMatchingInstances ]
					
		[p]	-> rewriteAppX_withInstance env xx 
				vOverloaded tOverloaded
				tsUseTypeArgs tsUseTypeArgsWitness
				xsValueArgs
				infoOverloaded p

	-- It's just regular, non-overload application, so leave it alone.
	| otherwise
	= xx

		
-- Ok, so we know what instance we're supposed to be using.
--	We now have to determine what type arguments we need to pass to the instance
--	function, so we can construct the call.
rewriteAppX_withInstance env xxUse
	vUse tUse
	tsUseTypeArgsPoly tsUseTypeArgsWitness
	xsValueArgs
	infoOverloaded p@PClassInst{}
	
 = seq (traceIt xxInst) xxInst
 where
	-- Instantiate the type of the overloaded var with its type arguments.
	--	This gives us the type that the overloaded var is being used at.
	tFlatScheme	= flattenT $ infoOverloadedType infoOverloaded
	tUseBody	= fromMaybe (panic stage $ "can't instantiate " % tFlatScheme)
			$ instantiateT tFlatScheme (tsUseTypeArgsPoly ++ tsUseTypeArgsWitness)

	-- Get the type of the instance.
	Just vInst	= lookup vUse (topClassInstMembers p)
	Just tInstScheme 
			= liftM flattenT
			$ takeFirstJust
			$ map (typeFromGlob vInst)
			$ envGlobs env

	tInstBody	= stripToBodyT $ tInstScheme
			
	-- Unify the body of the overloaded use with the body of the overloaded definition.
	-- This gives us the type args we need to pass to the body.
	sub		= fromMaybe panicUnify
			$ liftM Foldable.toList
			$ unifyTT tInstBody tUseBody

	-- BUGS: We're discarding constraints between effect and closure sums here...
	subArgs		= catMaybes
			$ map (\tt -> case tt of
					(TVar _ (UVar  v1),   t2)	-> Just (v1, t2)
					(TVar _ (UMore v1 _), t2)	-> Just (v1, t2)
					_				-> Nothing)
			$ sub
	
	-- Look at the quantifiers on the front of the scheme for the instance
	(vksQuant, _)	= slurpQuantVarsT tInstScheme
	tsInstTypeArgsPoly		
			= map	(\(v, k) -> fromMaybe (TVar k $ UVar v) $ lookup v subArgs) 
				vksQuant

	-- Instantate the scheme with the type args we have so far, 
	--	and look at the resulting type to determine what witnesses we have to pass.
	--	We can just use fabricate witnesses for now. Core.Thread will add the real ones later.
	Just tInstPoly			= instantiateT tInstScheme tsInstTypeArgsPoly
	(ksContext, _)			= slurpContextT  tInstPoly
	Just tsInstTypeArgsWitness 	= sequence $ map inventWitnessOfKind ksContext

	xxInst		= unflattenApps 
			$  Left (XVar vInst tInstScheme)
			:  [Right t	| t <- tsInstTypeArgsPoly]
			++ [Right t	| t <- tsInstTypeArgsWitness]
			++ xsValueArgs

	panicUnify 
	 = panic stage $ vcat
		[ ppr "rewriteAppX_withInstance: unification failed"
		, "    when rewriting expression:\n" %> xxUse
		, blank
		, "    tInstBody:  " % tInstBody
		, "    tUseBody:   " % tUseBody]

	traceIt x
	 = trace
	    ("Resolving overloaded application:\n" 
	    %> vcat	
		[ ppr xxUse
		, blank
		, ppr p
		, blank
		, "tUseBody              = " % tUseBody
		, blank
		, "tInstScheme           = " % tInstScheme
		, "tInstBody             = " % tInstBody
		, blank
		, "sub                   = " % sub
		, blank
		, "subArgs               = " % subArgs
		, "vksQuant              = " % vksQuant
		, "ksContext             = " % ksContext
		, "tsInstTypeArgsPoly    = " % tsInstTypeArgsPoly
		, "tsInstTypeArgsWitness = " % tsInstTypeArgsWitness
		, blank
		, "xxInst                = " % xxInst]) x


-- | Check if a type class instance matches some name and args.
--   eg:  for name 'Show' and args '[Int %r1]'
--
--        instance Show (Int %r5) where ...        matches
--   but: instance Show (Char %r6) where ..        does not.
--
instanceMatchesArgs 
	:: (Var, [Type])	-- Name and args of the instance we're looking for.
	-> (Var, [Type])	-- Name and args of a possible instance.
	-> Bool

instanceMatchesArgs  
	(vMatch, tsMatch)
	(vInst,  tsInst)

 	=  (vMatch                 == vInst)
	&& (length tsMatch         == length tsInst)
	&& (map kindOfType tsMatch == map kindOfType tsInst)
	&& (and $ zipWith typesMatch tsMatch tsInst)

typesMatch t1 t2 	
 = case unifyTT t1 t2 of 
	 Nothing	-> False
	 Just constrs	-> Foldable.and $ fmap subMatches constrs

subMatches (t1, t2)
	| TVar k _	<- t1
	= k == kindOfType t2
	
	| TVar k _	<- t2
	= k == kindOfType t1
	
	| otherwise
	= False

	
-- | Slurp the list of quantified variables, and requires witnesses
--	from the front of a type scheme.
slurpQuantVarsT :: Type  -> ([(Var, Kind)], Type)
slurpQuantVarsT tt
	= slurpQuantVarsT' tt []
		
slurpQuantVarsT' tt vsQuant
 = case tt of
	TForall (BVar v1) k1 t2
	 -> slurpQuantVarsT' t2 (vsQuant ++ [(v1, k1)])

	TForall (BMore v1 _) k1 t2
	 -> slurpQuantVarsT' t2 (vsQuant ++ [(v1, k1)])
	
	_ -> (vsQuant, tt)
	
	
slurpContextT :: Type -> ([Kind], Type)
slurpContextT tt
	= slurpContextT' tt []
	
slurpContextT' tt ksContext
 = case tt of
	TForall BNil k1 t2
	 -> slurpContextT' t2 (ksContext ++ [k1])
	
	_ -> (ksContext, tt)


