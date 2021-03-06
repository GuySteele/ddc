{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
{-# LANGUAGE NoMonomorphismRestriction #-}

-- | Elaborate data type definitions and type signatures in this tree.
--   In the source program we allow region, effect, and closure infomation to be elided
--   from data type definitions and type signatures.
--
--   For data type definitions, we add region effect and closure parameters using heuristics
--   based on how the data constructors are defined.
--
--   In type signatures we add fresh variables to data type constructor applications,
--   using the kind of the data type constructors as a guide. These varaiables are just
--   place holders, don't constrain the type, and just turn into 'meta' variables during
--   type inference.
--
--   NOTE: At the moment this only elaborates the effect and closure information
--         in type signatures. It runs after Desugar.Kinds which adds in missing region variables.

--   TODO: This is fairly ad-hoc at the moment, we'll need more experience with it to
--         determine if these heuristics are what we actually want. In all cases the
--         program should work if you add in all the required type information manually.
--
--   TODO: I expect we'll want to combine kind inference with this process in the long run.
--
module DDC.Desugar.Elaborate
	(elaborateTree)
where
import DDC.Source.Error
import DDC.Desugar.Elaborate.Quantify
import DDC.Desugar.Elaborate.EffClo
import DDC.Desugar.Elaborate.Constraint
import DDC.Desugar.Elaborate.Regions
import DDC.Desugar.Elaborate.Slurp
import DDC.Desugar.Elaborate.State
import DDC.Desugar.Glob
import DDC.Desugar.Exp
import DDC.Type.Data.Elaborate
import DDC.Type.Data
import DDC.Type
import DDC.Var
import DDC.Main.Error
import DDC.Main.Pretty
import Source.Desugar			(Annot(..))
import Data.List
import Data.Sequence			(Seq)
import Data.Map				(Map)
import Data.Set				(Set)
import qualified DDC.Type.Transform	as T
import qualified DDC.Desugar.Transform	as D
import qualified Data.Sequence		as Seq
import qualified Data.Set		as Set
import qualified Data.Map		as Map
import Data.Traversable			(mapM)
import Prelude				hiding (mapM)
import Control.Monad.State.Strict	hiding (mapM)
import Data.Maybe

stage 		= "DDC.Desugar.Elaborate"

-- | Elaborate types in this tree.
elaborateTree
	:: String		-- ^ Unique
	-> Glob Annot		-- ^ Header tree
	-> Glob Annot		-- ^ Module tree
	-> ( Glob Annot 	-- new header tree
	   , Glob Annot		-- new module tree
	   , Seq Constraint	-- the kind constaints
	   , Map Var Kind	-- the kind of every type constructor
	   , [Error])		-- errors found during elaboration

elaborateTree unique dgHeader dgModule
 = let
	((dgHeader', dgModule', constraints, errs), state')
		= runState
			(elaborateTreeM dgHeader dgModule)
			(stateInit unique)

   in	( dgHeader'
	, dgModule'
	, constraints
	, stateKinds state'
	, errs )

elaborateTreeM dgHeader dgModule
 = do
	-- Slurp out kind constraints from the program
 	let constraints	=      slurpConstraints dgHeader
			Seq.>< slurpConstraints dgModule

	-- Solve kind constraints
	solveConstraints constraints

	-- Remember kinds of class arguments to guide elaboration
 	let classes	=      slurpClasses dgHeader
			Seq.>< slurpClasses dgModule
	addClassKinds classes

	-- Update the kinds of all the type consructors
	-- TODO: huh? shouldn't this come after the next step?
	dgHeader_tagged	<- tagKindsInGlob dgHeader
	dgModule_tagged	<- tagKindsInGlob dgModule

	-- Elaborate data type definitions
	-- TODO: this probably needs to be merged with kind inference when it's ready
	-- TODO: the unpacking and repacking here is really horrible.
	let anHeader	= [ an | PData an _ <- Map.elems $ globDataDecls dgHeader_tagged]
	let anModule	= [ an | PData an _ <- Map.elems $ globDataDecls dgModule_tagged]

	let defsHeader	= fmap topDataDef $ globDataDecls dgHeader_tagged
	let defsModule	= fmap topDataDef $ globDataDecls dgModule_tagged

	(defsHeader', defsModule')
		<- elaborateDataDefs newVarN defsHeader defsModule

	let makeAnDefs glob anns defs
		= glob { globDataDecls = Map.fromList
			[ (dataDefName def, PData an def)
				| (an, def) <- zip anns (Map.elems defs) ] }

	let dgHeader_data = makeAnDefs dgHeader_tagged anHeader defsHeader'
	let dgModule_data = makeAnDefs dgModule_tagged anModule defsModule'


	-- Now that we know what the kinds of all the type constructors are,
	-- add missing reigon variables to type signatures.
	dgHeader_rs	<- elabRegionsInGlob dgHeader_data
	dgModule_rs	<- elabRegionsInGlob dgModule_data

	-- Elaborate effects and closures
	dgHeader_effclo	<- elaborateEffCloInGlob dgHeader_rs
	dgModule_effclo	<- elaborateEffCloInGlob dgModule_rs

	-- Attach data defs
	-- TODO: merge tagkinds above with this phase to save another walk over the code.
	let defsAll		= Map.union defsHeader' defsModule'
	let dgHeader_attach	= attachDataDefsToTyConsInGlob defsAll dgHeader_effclo
	let dgModule_attach	= attachDataDefsToTyConsInGlob defsAll dgModule_effclo

	-- Add missing forall quantifiers to sigs.
	let (dgHeader_quant, vsMono_, errsHeader)
				= elabQuantifySigsInGlob Set.empty dgHeader_attach

	let (dgModule_quant, vsMono,  errsModule)
				= elabQuantifySigsInGlob vsMono_   dgModule_attach

	-- See NOTE [Merging top-level monomorphic vars]
	let (dgModule_merged)	= mergeMonoVarsOfGlobs vsMono dgModule_quant

	return	( dgHeader_quant
		, dgModule_merged
		, constraints
		, errsHeader ++ errsModule)


-- | Find groups of vars with the same name and module id, pick one uniqueid
--   and substitute into all globs, source and header included.
mergeMonoVarsOfGlobs :: Set Var -> Glob a -> Glob a
mergeMonoVarsOfGlobs vsMono dgModule
 = let	vsGroups	= groupBy varsMatchByName $ Set.toList vsMono
	sub		= Map.unions
		 	$ [ Map.fromList $ zip rest (repeat v1)
				| (v1 : rest)	<- vsGroups
				, not $ null rest]

	transT		= T.transZM T.transTableId
			{ T.transV = \v -> return $ fromMaybe v (Map.lookup v sub) }

	transP		= D.transZ (D.transTableId return)
			{ D.transT = transT }

   in	dgModule { globTypeSigs = Map.map (map transP) (globTypeSigs dgModule) }


-- Tag Kinds --------------------------------------------------------------------------------------
-- | Tag each data constructor with its kind from this table
tagKindsInGlob :: Glob Annot -> ElabM (Glob Annot)
tagKindsInGlob pp
	= D.transZM (D.transTableId return)
		{ D.transN      = tagKindsN Map.empty
		, D.transT	= tagKindsT Map.empty }
		pp


-- | Tag type constructors in type annots with their kinds.
tagKindsN :: Map Var Kind -> Annot -> ElabM Annot
tagKindsN local (Annot sp (Just t))
 = do   t'      <- tagKindsT local t
        return  $ Annot sp (Just t')

tagKindsN _ n
 = return n


-- | Tag type constructors in types with their kinds.
tagKindsT :: Map Var Kind -> Type -> ElabM Type
tagKindsT local tt
 = case tt of
	TVar _ (UVar v)
	 -> do	kindMap	<- gets stateKinds
		case listToMaybe $ catMaybes [Map.lookup v kindMap, Map.lookup v local] of
			Nothing	-> return $ tt
			Just k'	-> return $ TVar k' $ UVar v

	TCon (TyConData v _ mDef)
	 -> do	kindMap	<- gets stateKinds
		case listToMaybe $ catMaybes [Map.lookup v kindMap, Map.lookup v local] of
			Nothing	-> return tt
			Just k'	-> return $ TCon (TyConData v k' mDef)

	TCon{}
	 -> return tt

	TSum k ts
	 -> liftM2 TSum (return k) (mapM (tagKindsT local) ts)

	TApp t1 t2
	 -> liftM2 TApp (tagKindsT local t1) (tagKindsT local t2)

	TForall b k t
	 | Just v	<- takeVarOfBind b
	 -> do	let local'	= Map.insert v k local
		t'		<- tagKindsT local' t
		return		$ TForall b k t'

	TForall b k t
	 -> liftM3 TForall (return b) (return k) (tagKindsT local t)

	TConstrain t crs
	 -> liftM2 TConstrain (tagKindsT local t) (tagKindsCrs local crs)

	_ -> panic stage $ "tagKindsT: no match for " % tt


tagKindsCrs :: Map Var Kind -> Constraints -> ElabM Constraints
tagKindsCrs local crs
 = liftM3 Constraints
		(mapM (tagKindsT local) $ crsEq   crs)
		(mapM (tagKindsT local) $ crsMore crs)
		(return $ crsOther crs)


-- Attach -----------------------------------------------------------------------------------------
-- | Attach DataDefs to all TyCons in a glob.
--   This makes it easy to get the def when consuming the type.
attachDataDefsToTyConsInGlob :: Map Var DataDef -> Glob Annot -> Glob Annot
attachDataDefsToTyConsInGlob defs glob
	= D.transZ (D.transTableId return)
		{ D.transN      = \n -> return $ attachDataDefsN defs n
		, D.transT	= \t -> return $ T.transformT (attachDataDefsT defs) t }
		glob


-- | Attach data defs to tycons in a type annot
attachDataDefsN :: Map Var DataDef -> Annot -> Annot
attachDataDefsN defs nn
 = case nn of
        Annot sp (Just t)       -> Annot sp (Just $ T.transformT (attachDataDefsT defs) t)
        _                       -> nn
        

-- | Attach data defs to tycons in a type.
attachDataDefsT :: Map Var DataDef -> Type -> Type
attachDataDefsT defs tt
	| TCon (TyConData v k Nothing)	<- tt
	, Just def			<- Map.lookup v defs
	= TCon (TyConData v k (Just def))

	| otherwise
	= tt


-- EffClo -----------------------------------------------------------------------------------------
-- | Elaborate effects and closures in a top level signature.
elaborateEffCloInGlob :: Glob Annot -> ElabM (Glob Annot)
elaborateEffCloInGlob glob
 = do	externs'	<- mapM elaborateEffCloP (globExterns glob)
	typesigs'	<- mapM (mapM elaborateEffCloP) (globTypeSigs glob)
	return	$ glob 	{ globExterns	= externs'
			, globTypeSigs	= typesigs' }

elaborateEffCloP :: Top Annot -> ElabM (Top Annot)
elaborateEffCloP pp
  = case pp of
	PExtern ann v t mt
	 -> do	t'	<- elaborateEffCloInFunSigT t
		return	$ PExtern ann v t' mt

	PTypeSig a sigMode vs t
	 -> do	t'	<- elaborateEffCloInFunSigT t
		return	$ PTypeSig a sigMode vs t'

	_ -> return pp


---------------------------------------------------------------------------------------------------

{-	NOTE [Merging top-level monomorphic vars]
	~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

	Consider the following program:
	  x :: Int %r1

	  f :: Int %r2 -($c1)> Int %r3
	    :- $c1 = ${%r1}
	  f = ...

	Note that both occurrences of %r1 are monomorphic because they appear
	in material positions. However, because the renamer renames each
	signature in its own context, the two occurrences of %r1 will have
	different unique ids. This is because the renamer assumes that forall
	quantifiers will be added for every free variable in a signature.

	Here in the elaborator though, we don't add foralls for material vars.
	Of course, the renamer can't know what vars are material because the
	materiality of the data type of interest might not have been computed then.

	For comparison, suppose we added an explicit region binder at top level:

	 region %r1

	In this case we'd be ok: all occurrences of %r1 would have the same uniqueid.
	However, as we don't want to require every top-level region to be explicitly
	defined, we must instead collect up groups of monomorphic top level region
	vars with the same name and moduleid, and rewrite them so they also have the
	same unqiue. In effect we're finishing the job of the renamer based on the
	materiality information we've just computed.
-}

