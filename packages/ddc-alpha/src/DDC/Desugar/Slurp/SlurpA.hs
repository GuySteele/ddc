{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
module DDC.Desugar.Slurp.SlurpA
	(slurpA)
where
import DDC.Desugar.Slurp.Base
import DDC.Desugar.Slurp.SlurpX
import DDC.Type.Data.Base
import DDC.Solve.Location
import DDC.Var
import Source.Desugar		(Annot, spOfAnnot)
import Data.Bag			(Bag)
import qualified Data.Bag	as Bag
import Util

stage	= "DDC.Desugar.Slurp.SlurpA"

-- | Slurp out type constraints from a match alternative.
slurpA	:: Alt Annot
	-> CSlurpM
		( Type		-- type constraint placed on the case object.
		, Type		-- type of the RHS.
		, Effect	-- effect of evaluating the alternative.
		, Closure	-- closure of this alternative.
		, Alt Annot2	-- annotated Alt.
		, CTree)	-- constraints.

slurpA	(AAlt annot gs x)
 = do
	tGuards	<- newTVarDS "guards"
	eAlt	<- newTVarES "alt"

	-- slurp the guards
	--	we need to do this before slurping the RHS
	--	because slurpW sets the bindMode for any matched vars.
	--
	-- BUGS?: we're not using the guards, check this

	(cbindssGuards, mtsGuards, esGuards, _csGuards, gs', qssGuards)
				<- liftM unzip6 $ mapM slurpG gs

	-- slurp the RHS of the alternative
	(tX, eX, _, x', qsX)	<- slurpX x

	let qs	=  makeCEqs (TSU $ SUGuards (spOfAnnot annot)) (tGuards : catMaybes mtsGuards)
		++ [CMore (TSE $ SEGuards (spOfAnnot annot)) eAlt $ makeTSum   kEffect  (eX : esGuards)]

	let cbindsGuards	= concat cbindssGuards
	let bind
		| []	<- cbindsGuards
		= BNothing

		| otherwise
		= BDecon [vDeconT | (_, vDeconT) <- cbindsGuards]

	return	( tGuards
		, tX
		, eAlt
		, tEmpty
		, AAlt Nothing gs' x'
		, CBranch
			{ branchBind	= bind
			, branchSub	= qs ++ (Bag.toList $ Bag.concat qssGuards >< qsX) } )


-- Guards ------------------------------------------------------------------------------------------
slurpG 	:: Guard Annot
	-> CSlurpM
		( [(Var, Var)]		-- (value var, type var) of vars bound by the guard.
		, Maybe Type		-- type constraint placed on case object.
		, Effect		-- effect of evaluting the guard.
		, Closure		-- closure of guard.
		, Guard Annot2		-- annotated guard.
		, Bag CTree)		-- constraints.

slurpG	(GCase _ w)
 = do
 	(cbindsW, tW, w', qsW)
 		<- slurpW w

 	return	( cbindsW
		, Just tW
		, tPure
		, tEmpty
		, GCase Nothing w'
		, qsW )


slurpG	(GExp annot w x)
 = do
	eGuard			<- newTVarES "guard"
	(cbindsW, tW, w', qsW) 	<- slurpW w

	-- slurp the matched exp
	(tX, eX, _, x', qsX)	<- slurpX x

	-- make the effect of testing the case object
	let effMatch
		= case w of
			-- if the LHS is a plain var there is no effect
			WVar{}	-> []

			-- otherwise we need to read the primary region
			_	-> [TApp tHeadRead tX]

	let qs = constraints
		[ CEq	(TSU $ SUGuards (spOfAnnot annot))	tX	$ tW
		, CMore	(TSE $ SEGuardObj (spOfAnnot annot))	eGuard	$ makeTSum kEffect (eX : effMatch) ]

	return	( cbindsW
		, Nothing
		, eGuard
		, tEmpty
		, GExp Nothing w' x'
		, qsW >< qsX >< qs )


-- Pat ---------------------------------------------------------------------------------------------
slurpW	:: Pat Annot
	-> CSlurpM
		( [(Var, Var)]		-- (value var, type var) of vars bound by pattern.
		, Type			-- type of the pattern.
		, Pat Annot2		-- annotatted pattern.
		, Bag CTree)		-- constraints for each arg in the pattern.

slurpW	(WConLabel _ vCon lvs)
 = do
	-- Lookup what data type this constructor belongs to.
	mDataDef	<- lookupDataDefOfCtorNamed vCon
	let dataDef	= fromMaybe (panic stage
					$ "slurpW: can't find type data type definition for data constructor '"
					% vCon % "'")
			$ mDataDef

	let vksParam	= dataDefParams dataDef

	-- Instantiate each of the vars in the data type.
	vsInst		<- mapM newVarZ $ map fst vksParam
	let Just ksInst	=  sequence $ map (kindOfSpace . varNameSpace) vsInst
	let tsInst	=  zipWith TVar ksInst $ map UVar vsInst

	-- This is the type the pattern must be.
	let tPat	= makeTData
				(dataDefName dataDef)
				(makeKFuns (map snd vksParam) kValue)
				tsInst

	-- Slurp constraints for each of the bound fields.
	(lvs', cBinds, cTrees)
			<- liftM unzip3
			$  mapM (slurpLV vCon tsInst) lvs

 	return	( catMaybes cBinds
		, tPat
		, WConLabel Nothing vCon lvs'
		, Bag.concat cTrees )


slurpW	(WLit annot litFmt)
 = do
	tD@(TVar _ (UVar tV))	<- newTVarDS "const"
	tE			<- newTVarES "const"

	-- work out the type of this literal
	let Just TyConData
		{ tyConName 	= tcVar
		, tyConDataKind = tcKind }
		= tyConOfLiteralFmt litFmt

	-- if the literal type needs a region var then make a fresh one
	let tLitM
		| tcKind == kValue
		= return $ makeTData tcVar tcKind []

		| tcKind == KFun kRegion kValue
		= do	vR	<- newVarN NameRegion
			return	$ makeTData tcVar tcKind [TVar kRegion $ UVar vR]

		| otherwise
		= panic stage $ "tLitM: no match"


	tLit <- tLitM

	wantTypeV tV

 	return	( []
		, tD
		, WLit (Just (tD, tE)) litFmt
		, constraints [CEq (TSV $ SVLiteralMatch (spOfAnnot annot) litFmt) tD tLit])


slurpW	(WVar _ v)
 = do	tBound@(TVar _ (UVar vT))	<- lbindVtoT v

	return	( [(v, vT)]
		, tBound
		, WVar (Just (tBound, tPure)) v
		, Bag.empty)

slurpW w
 = panic stage $ "slurpW: no match for " % show w % "\n"


-- Labels ------------------------------------------------------------------------------------------
slurpLV	:: Var				-- ^ Data constructor name.
	-> [Type]			-- ^ Parameter types of data type constructor
	-> (Label Annot, Var)		-- ^ Field label and var to bind that field to.
	-> CSlurpM
		( (Label Annot2, Var)	-- field label and orginal binding var
		, Maybe (Var, Var)	-- original binding variable, and type var for that field.
		, Bag CTree )

-- A field label using a numeric index.
slurpLV vCtor tsParams (LIndex annot ix, vBind)
 = do
	-- create a new type var for this arg.
 	(TVar _ (UVar vT))	<- lbindVtoT vBind
	wantTypeV vT

	-- Get the ctor definition.
	Just ctorDef	<- lookupCtorDefOfCtorNamed vCtor

	case lookupTypeOfNumberedFieldFromCtorDef ix ctorDef of
         -- Uh oh, there's no field with this index.
	 --	Add the error to the monad and return some dummy info so
	 --	that the slurper can proceed and maybe find more errors.
	 Nothing
	  -> do	addError
	   	  (ErrorCtorArity
			{ eCtorVar	= vCtor
			, eCtorArity	= ctorDefArity ctorDef
			, ePatternArity	= ix + 1})

		let v	= varWithName "<error>"

		return	( (LVar Nothing v, v)
			, Nothing
			, Bag.empty )

	 -- Got the type of the field.
	 -- The field type comes with the same outer forall quantifiers that
	 -- were on the scheme for the whole constructor type.
	 Just tField
	  -> let Just tField_inst = instantiateT tField tsParams
	     in	 return ( (LIndex Nothing ix, vBind)
			, Just (vBind, vT)
			, constraints [CEq (TSV $ SVMatchCtorArg (spOfAnnot annot)) (TVar kValue $ UVar vT) tField_inst] )


slurpLV vCtor tsParams (LVar annot vField, vBind)
 = do 	-- Create a new type var for this arg.
 	Just (TVar _ (UVar vT))	<- bindVtoT vBind
	wantTypeV vT

	-- Get the ctor definition.
	Just ctorDef	<- lookupCtorDefOfCtorNamed vCtor

	-- Lookup the fields for this constructor.
	case lookupTypeOfNamedFieldFromCtorDef vField ctorDef of

	 -- If the field refered to doesn't exist this should have
	 -- been detected by the renamer.
	 Nothing
	  -> panic stage $ "slurpLV: no field named " % vField

	 Just tField
 	  -> let Just tField_inst = instantiateT tField tsParams
	     in	 return	( (LVar Nothing vField, vBind)
 			, Just (vBind, vT)
			, constraints [CEq (TSV $ SVMatchCtorArg (spOfAnnot annot)) (TVar kValue $ UVar vT) tField_inst] )
