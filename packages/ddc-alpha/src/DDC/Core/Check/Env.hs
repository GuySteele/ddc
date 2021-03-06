{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | Type environment and configuration for the core type checker.
module DDC.Core.Check.Env
	( Env(..)
	, envInit
	, envEmpty
	, withType
	, withKindBound
	, withKindBounds
	, typeFromEnv
	, witnessConstFromEnv)
where
import DDC.Main.Error
import DDC.Main.Pretty
import DDC.Core.Exp
import DDC.Core.Glob
import DDC.Type
import DDC.Var
import Data.List
import Control.Monad
import Data.Map			(Map)
import qualified Data.Map	as Map

stage	= "DDC.Core.Lint.Env"

-- | A table of type and kind bindings.
data Env

	= Env
	{ -- | The name of the thing that invoked this lint pass.
	  --   Printed in panic messages.
	  envCaller		:: String
	
	  -- | Whether the thing we're checking is supposed to be closed.
	  --   Bound variable occurrences must be present in the environment when we get to them.
	, envClosed		:: Bool

	  -- | The header glob, for getting top-level types and kinds.
	, envHeaderGlob		:: Glob

	  -- | The core glob, for getting top-level types and kinds.
	, envModuleGlob		:: Glob

	  -- | Types of value variables that are in scope at the current point.
	, envTypes		:: Map Var Type

	  -- | Kinds of type variables that are in scope at the current point,
	  ---  with optional :> constraint.
	, envKindBounds		:: Map Var (Kind, Maybe Type) }
	

envInit	caller cgHeader cgModule
	= Env
	{ envCaller		= caller
	, envClosed		= True
	, envHeaderGlob		= cgHeader
	, envModuleGlob		= cgModule
	, envTypes		= Map.empty
	, envKindBounds		= Map.empty }

envEmpty caller
	= envInit caller globEmpty globEmpty

-- | Run a lint computation with an extra type in the environment.
withType :: Var -> Type -> Env -> (Env -> a) -> a
withType v t env fun
 = let	addVT Nothing	= Just t
	addVT Just{}	= panic stage $ "withVarType: type for " % v % " already present"
   in	fun $ env { envTypes = Map.alter addVT v (envTypes env) }


-- | Run a lint computation with an extra kind in the environment.
--   NOTE: We allow a type var to be rebound with the same kind, which makes
--         desugaring of projection puns easier.
--   TODO: we could also check we're not rebinding a type with a different :> constraint.
-- 
withKindBound :: Var -> Kind -> Maybe Type -> Env -> (Env -> a) -> a
withKindBound v k mt env fun
 	= withKindBounds [(v, k, mt)] env fun

withKindBounds :: [(Var, Kind, Maybe Type)] -> Env -> (Env -> a) -> a
withKindBounds vkmts env fun
 = let	
	addVK _ k mt Nothing	= Just (k, mt)
	addVK v k mt (Just (k', _))
	 | k == k'	= Just (k, mt)
	 | otherwise	= panic stage $ "withVarKind: " % v % " rebound with a different kind"

	update (v, k, mt)
		= Map.alter (addVK v k mt) v

	kindBounds'	= foldr update (envKindBounds env) vkmts

	env'		= env { envKindBounds = kindBounds' }
   in	fun $ env'


-- | Lookup the type of some value variable from the environment.
typeFromEnv :: Var -> Env -> Maybe Type
typeFromEnv v env
	| varNameSpace v /= NameValue
	= panic stage $ "typeFromEnv: wrong namespace for " % v

	-- Variable was locally bound.
	| Just t <- Map.lookup v   $ envTypes env	= Just t

	-- Variable was bound at top level.
	| Just t <- typeFromGlob v $ envModuleGlob env	= Just t

	-- Variable was bouna at top level in an imported module.
	| Just t <- typeFromGlob v $ envHeaderGlob env	= Just t

	-- No dice.
	| otherwise 
	= Nothing
	
	
-- | Lookup the var of the witness that guarantees the constancy of a region, if any.
witnessConstFromEnv :: Var -> Env -> Maybe Var
witnessConstFromEnv vr env
	| varNameSpace vr /= NameRegion
	= panic stage $ "witnessConstFromEnv: var " % vr % " should be a region var"

	| Just (PRegion _ vts)	<- Map.lookup vr $ globRegion (envHeaderGlob env)
	= liftM fst $ find (\(_, t) -> isConst vr t) vts

	| Just (PRegion _ vts)	<- Map.lookup vr $ globRegion (envModuleGlob env)
	= liftM fst $ find (\(_, t) -> isConst vr t) vts
	
	| otherwise
	= Nothing

	where isConst r t
		| TApp t1 t2		<- t
		, TVar _ (UVar v)	<- t2
		, t1 == tMkConst
		, v  == r
		= True
		
		| otherwise
		= False
		
		
		



