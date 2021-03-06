{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | Slurp constraints for kind inference from a desugared source tree.
module DDC.Desugar.Elaborate.Slurp
	( slurpConstraints
	, slurpClasses )
where
import Shared.VarPrim
import DDC.Desugar.Elaborate.Constraint
import DDC.Desugar.Glob
import DDC.Desugar.Exp
import DDC.Type
import DDC.Type.Data
import DDC.Var
import Source.Desugar		(Annot, spOfAnnot)
import Data.Sequence		as Seq


-- | Slurp kind constraints from the desugared module
slurpConstraints :: Glob Annot -> Seq Constraint
slurpConstraints dg
	= Seq.fromList
	$ concatMap slurpConstraint
	$ treeOfGlob dg

slurpConstraint pp
 = case pp of
 	PKindSig annot v k
 	 | resultKind k == kEffect
	 -> [Constraint (KSEffect (spOfAnnot annot)) v k]

	 | otherwise
	 -> [Constraint (KSSig (spOfAnnot annot)) v k]

	PClassDecl annot _ ts _
	 -> map (\t -> 	let TVar k (UVar v)	= t
			in Constraint (KSClass (spOfAnnot annot)) v (defaultKind v k)) ts

 	PData annot def@(DataDef{})
	 -> let	k	= dataDefKind def
	        k'	= forcePrimaryRegion (dataDefName def) k
	    in	[Constraint (KSData (spOfAnnot annot)) (dataDefName def) k']

	_	-> []


defaultKind v k
 	| k == KNil
	= let Just k' = kindOfSpace $ varNameSpace v
	  in  k'

	| otherwise	= k


-- Ensure the kinds of data type constructors have their primary regions.
forcePrimaryRegion :: Var -> Kind -> Kind
forcePrimaryRegion vData k

	-- unit doesn't need one
 	| vData == primTUnit
	= k

	-- these abstract types don't need one
	| elem vData [primTObj, primTData, primTThunk]
	= k

	-- unboxed data types don't need one
	| varIsUnboxedTyConData vData
	= k

	-- don't elaborate types with higher kinds
	| KFun kR _	<- k
	, kR	== kRegion
	= k

	| otherwise
	= KFun kRegion k

-- | Slurp kinds of class arguments
slurpClasses :: Glob a -> Seq (Var,[Kind])
slurpClasses dg
	= Seq.fromList
	$ concatMap slurpClass
	$ treeOfGlob dg

slurpClass (PClassDecl _ v ts _)
 = let	kinds = map (\t -> let TVar k _ = t in k) ts
	in [(v,kinds)]
slurpClass _
 = []

