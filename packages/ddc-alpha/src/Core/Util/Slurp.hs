
module Core.Util.Slurp
	( slurpTypesP
	, maybeSlurpTypeX
 	, slurpTypeMapPs
	, slurpSuperMapPs
	, slurpCtorDefs 
	, slurpExpX
	, slurpBoundVarsP
	, slurpBoundVarsW
	, dropXTau)
where
import Type.Util
import DDC.Main.Error
import DDC.Core.Pretty		()
import DDC.Core.Exp
import DDC.Type
import DDC.Type.Data.Base
import DDC.Var
import qualified Data.Map	as Map
import Util

stage	= "Core.Util.Slurp"

-- | Slurp out the types defined by this top level thing
slurpTypesP :: Top -> [(Var, Type)]
slurpTypesP pp
 = case pp of
	PExtern v tv to	-> [(v, tv)]
	PBind   v x
	 -> case maybeSlurpTypeX x of
	 	Just t	-> [(v, t)]
		Nothing	-> panic stage
			$ "Core.Util.Slurp: slurpTypesP\n"
			% "  can't get type from this top-level thing\n"
			% pp % "\n\n"

	PClassDict v ts sigs -> sigs
	_ -> []


-- | The types of top level things can be extracted directly from their annotations, 
--	without having to do a full type reconstruction.
maybeSlurpTypeX :: Exp -> Maybe Type
maybeSlurpTypeX	xx
	| XLAM v k@(KApp{}) x	<- xx
	, Just x'		<- maybeSlurpTypeX x
	= Just $ TForall BNil k x'

 	| XLAM v k x		<- xx
	, Just x'		<- maybeSlurpTypeX x
	= Just $ TForall v k x'
	
	| XLam v t x eff clo	<- xx
	, Just x'		<- maybeSlurpTypeX x
	= Just $ makeTFun t x' eff clo
	
	| XTau t x		<- xx
	= Just t

	| otherwise
	= Nothing

-- | Slurp out a map of types of top level things
slurpTypeMapPs ::	[Top] -> Map Var Type
slurpTypeMapPs ps
 	= Map.fromList
	$ catMap slurpTypesP ps

-- | Slurp out a map of all top-level super combinators
slurpSuperMapPs ::	[Top] -> Map Var Top
slurpSuperMapPs	ps
	= Map.fromList
	$ [ (v, p) | p@(PBind v _) <- ps]
	

-- | Slurp out the body expression from this annotated thing.
slurpExpX ::	Exp -> Exp
slurpExpX xx
 = case xx of
 	XLAM 	v k x	-> slurpExpX x
	XTau 	t x	-> slurpExpX x
	_		-> xx

-- | Slurp out all the constructors defined in this tree
slurpCtorDefs :: Tree -> Map Var CtorDef
slurpCtorDefs tree
 	= Map.unions
	$ [ dataDefCtors def | p@(PData def)	<- tree ]

-- | Slurp out a list of vars bound by this top level thing
slurpBoundVarsP :: Top -> [Var]
slurpBoundVarsP pp
 = case pp of
 	PBind   v x		-> [v]
	PExtern v t1 t2		-> [v]
	PData{}
	 -> (dataDefName $ topDataDef pp) 
		: Map.keys (dataDefCtors $ topDataDef pp)

	PClassDict v ts vts	-> map fst vts
	PClassInst{}		-> []

	PRegion v vts		-> v : map fst vts
	PEffect	v k		-> [v]
	PClass 	v k		-> [v]
	

-- | Slurp out the list of vars bound by a pattern.
slurpBoundVarsW :: Pat -> [Var]
slurpBoundVarsW ww
 = case ww of
	WVar v		-> [v]
	WLit{}		-> []
	WCon _ _ lvts	-> [v | (_, v, _) <- lvts]


-- | Decend into this expression and annotate the first value found with its type
--	doing this makes it possible to slurpType this expression
--
dropXTau :: Exp -> Map Var Type -> Type -> Exp
dropXTau xx env tt
	-- load up bindings into the environment
	| TConstrain t crs	<- tt
	= panic stage $ "dropXTau: Reconstructed types should have TConstrain nodes"

	-- decend into XLAMs
	| XLAM v t x		<- xx
	, TForall BNil k1 t2	<- tt
	= XLAM v t $ dropXTau x env t2

	| XLAM v t x		<- xx
	, TForall v t1 t2	<- tt
	= XLAM v t $ dropXTau x env t2
		
	-- decend into XLams
	| XLam v t x eff clo	<- xx
	, Just (_, t2, _, _)	<- takeTFun tt
	= XLam v t (dropXTau x env t2) eff clo
	
	-- there's already an XTau here,
	--	no point adding another one, 
	--	bail out
	| XTau t x		<- xx
	= xx
	
	-- we've hit a value, drop the annot
	| otherwise
	= XTau (packT $ makeTWhere tt (Map.toList env)) xx


