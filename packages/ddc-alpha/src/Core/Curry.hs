
-- | Work out how to perform function applications and rewrites them into
--   super-call/curry/apply/tail-calls.
module Core.Curry
	(curryGlob)
where
import Core.Util
import Util
import DDC.Main.Pretty
import DDC.Main.Error
import DDC.Type
import DDC.Core.Exp
import DDC.Core.Glob
import DDC.Var
import qualified Data.Set	as Set
import qualified Shared.VarUtil	as Var
import qualified Debug.Trace	as Debug

stage		= "Core.Curry"
debug		= False
trace s	x 	= if debug then Debug.trace (pprStrPlain s) x else x


-- | Environment for this transform
data Env
	= Env
	{ envGlobHeader		:: Glob
	, envGlobProg		:: Glob }


-- | Work out how to perform function applications in this tree
--	rewrite them to use the primitive application operators.
curryGlob
	:: Bool			-- ^ Whether to do tail-recursion optimisation.
	-> Glob			-- ^ Header glob.
	-> Glob			-- ^ Source glob.
	-> Glob 

curryGlob 
	optTailCall
	headerGlob
	progGlob
 = let 	env	= Env headerGlob progGlob
   in   mapBindsOfGlob (curryP optTailCall env) progGlob


curryP optTailCall env p
 = case p of
 	PBind v x
	 | optTailCall
	 -> PBind v (curryX env (Set.singleton v) x)
	 
	 | otherwise
	 -> PBind v (curryX env Set.empty x)
	 
	_ -> p
	

-- | Rewrite function applications in this statement
curryS 	:: Env 
	-> Set Var		-- ^ Names of supers that can be tail-called in this statement.
	-> Stmt 		-- ^ Statement to transform.
	-> Stmt

curryS env vsTailCall s
 = case s of
	SBind v x	-> SBind v (curryX env vsTailCall x)

   
-- | Rewrite function applications in this expression
curryX	env vsTailCall xx
	-- boilerplate.
	| XLAM v k x		<- xx	= XLAM v k (downX x)
	| XLam v t x eff clo	<- xx	= XLam v t (downX x) eff clo
	| XTau t x		<- xx	= XTau t	$ downX x
	| XLocal v vs x		<- xx	= XLocal v vs	$ downX x
	| XMatch aa		<- xx	= XMatch 	$ map downA aa
	| XPrim{}		<- xx	= xx
	| XLit{} 		<- xx	= xx

	-- A zero arity super.
	| XVar v t		<- xx
	= if   (varIsBoundAtTopLevelInGlob (envGlobHeader env) v)
	    || (varIsBoundAtTopLevelInGlob (envGlobProg   env) v)
	   then	fromMaybe xx $ makeCall env vsTailCall xx []
	   else xx
	
	| XDo ss		<- xx
	= let	initSS		= init ss
		Just lastS	= takeLast ss
				
		initSS'		= map (curryS env Set.empty) initSS
		lastS'		= curryS env vsTailCall lastS

	  in	XDo (initSS' ++ [lastS'])
		
	-- Applications.
	| (xx =@= XAPP{}) || (xx =@= XApp{})
	= case flattenApps xx of
		-- Application of a literal.
		Left XLit{}    : _	-> xx

		-- Application of a primitive function.
		Left XPrim{}   : _	-> xx

		-- Application of a real function.
		Left xF@XVar{} : args
		 | Just xx'		<- makeCall env vsTailCall xF args
		 -> xx'
		
		-- Type appliations of a plain variable (not a function)
		Left xF@XVar{} : args
		 | []	<- [x | Left x <- args]
		 -> xx
		
		-- Oh oh..
		parts	-> panic stage 
			$ "curryX: this looks like a function application but I dunno how to make the call"
		 	% parts
		
	
	-- uh oh..			
	| otherwise	
	= panic stage
	$ "curryX: no match for " % show xx % "\n"

	where 	downX	= curryX env vsTailCall
		downA	= curryA env vsTailCall


-- | Rewrite function applications in this alternative
curryA env vsTailCall (AAlt gs x)
	= AAlt 	(map (curryG env vsTailCall) gs) 
		(curryX env vsTailCall x)


-- | Rewrite function applicatoin in this guard
curryG env vsTailCall (GExp w x)
	= GExp w
	 	(curryX env Set.empty x)


-- | Make a call to a function.
--	We need to decide whether we have less than, enough, or more args than the super wants.
--	If less then, 	then we make a partial application.
--	If enough,	then we can call the super directly.
--	If more than,	then we call the super then make a parial application for the rest.
--
makeCall 	
	:: Env			
	-> Set Var		-- ^ Names of supers that can be tailcalled from here
	-> Exp			-- ^ Call this function (must be an XVar)
	-> [Either Exp Type] 	-- ^ args to function
	-> Maybe Exp

makeCall env vsTailCall xF@(XVar vF tF) args
 = let	callArity	= length [ x | Left x <- args]
			
	result
 	 -- Function is a top-level super.
	 | Just superArity	
		<- takeFirstJust [ bindingArityFromGlob vF $ envGlobHeader env
				 , bindingArityFromGlob vF $ envGlobProg   env ]
	 = trace	( "* makeCall:\n"
	  		% " f           = "	% vF % "\n"
			% " callArity  = " 	% callArity	% "\n"
			% " superArity = "	% superArity	% "\n")
			$ makeSuperCall xF vsTailCall args callArity superArity
				
	 -- Function is represented as a thunk instead of a super.
	 | otherwise
	 =  makeThunkCall xF args callArity
	
   in	result
	
makeCall env vsTailCall xF args
	= panic stage
	$ "makeCall: no match for " % xF	% "\n"


-- | We've got a top-level supercombinator that we can call directly.
makeSuperCall 
	:: Exp 			-- ^ Name of super being called.	(must be an XVar)
	-> Set Var		-- ^ Supers that can be tail called.
	-> [Either Exp Type] 	-- ^ Arguments to super.
	-> Int 			-- ^ Number of args in the call.
	-> Int 			-- ^ Number of args needed by the super.
	-> Maybe Exp

makeSuperCall 
	xF@(XVar vF tF)
	tailCallMe args callArity superArity
 
	-- The values of CAFs are shared between calls to them..
	--	The Sea stages handle initialisation of them.
 	| superArity	== 0
	, callArity 	== 0
	, not $ Var.isCtorName vF
	= Just xF

	-- We've got the exact number of args the super needs and we're ok
	-- 	for a tail-call. 
 	| callArity == superArity
	, Set.member vF tailCallMe
	= buildApp $ (Left $ XPrim (MCall (PrimCallTail vF)) tF) : args

	-- We're not able to do a tail call, but we've still got the right number
	--	of arguments, so we can call the super directly.
	| callArity == superArity
	= buildApp $ (Left $ XPrim (MCall (PrimCallSuper vF)) tF) : args

	-- We haven't got enough args to call the super yet, we'll have to build
	--	a thunk and wait for more.
	| callArity <  superArity
	= buildApp $ (Left $ XPrim (MCall (PrimCallCurry vF superArity)) tF) : args

	-- We've got more args than the super will accept.
	--	For this case to be well typed, the super must be returning a thunk.
	--	XCallApp instructs the runtime system to call the super to get the thunk
	--	and then apply the rest of the arguments to it.
	| callArity > superArity
	= buildApp $ (Left $ XPrim (MCall (PrimCallSuperApply vF superArity)) tF) : args
   	
	
-- | Apply a thunk to a value to get the result.
makeThunkCall :: Exp -> [Either Exp Type] -> Int -> Maybe Exp
makeThunkCall xF@(XVar vF tF) args callArity

	-- If there were only type applications, but no values being applied, 
	--	then the callAirity is zero and there is no associated call at Sea level.
	| callArity == 0
	= Nothing
	
	-- Otherwise we have actual arguments being applied to a thunk.
	| otherwise
	= buildApp $ (Left $ XPrim (MCall (PrimCallApply vF)) tF) : args

