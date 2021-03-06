{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | Tracking the source locations corresponding to type constraints and errors.
module DDC.Solve.Location
	( TypeSource 	(..)
	, SourceValue	(..)
	, SourceEffect	(..)
	, SourceClosure (..)
	, SourceUnify	(..)
	, SourceMisc	(..)
	, SourceInfer	(..)

	, takeSourcePos
	, dispSourcePos
	, dispTypeSource
	, dispSourceValue
	, dispFetterSource)
where
import Shared.VarPrim
import DDC.Solve.Graph.Node
import DDC.Main.Pretty
import DDC.Main.Error
import DDC.Base.SourcePos
import DDC.Base.Literal
import DDC.Type
import DDC.Var

stage	= "DDC.Solve.Location"

-- | Records where type constraints come from
--	These are used for producing nice error messages when a type error is found during inference
data TypeSource
	-- A dummy typesource for hacking around
	--	this shouldn't be present in deployed code.
	= TSNil	String

	-- These are positions from the actual source file.
	| TSV SourceValue			-- ^ Constraints on value types
	| TSE SourceEffect			-- ^ Constraints on effect types
	| TSC SourceClosure			-- ^ Constraints on closure types
	| TSU SourceUnify			-- ^ Why types were unified
	| TSM SourceMisc			-- ^ Other source of type things

	-- Things that were added to the graph by the type inferencer.
	| TSI SourceInfer
	deriving (Show, Eq)


instance Pretty TypeSource PMode where
 ppr (TSNil str) = "TSNil" %% ppr str
 ppr (TSV sv)	 = "TSV"   %% ppr sv
 ppr (TSE se)	 = "TSE"   %% ppr se
 ppr (TSC sc)	 = "TSC"   %% ppr sc
 ppr (TSU su)	 = "TSU"   %% ppr su
 ppr (TSM sm)	 = "TSM"   %% ppr sm
 ppr (TSI si)	 = "TSI"   %% ppr si


-- | Sources of value constraints
data SourceValue
	= SVLambda	{ vsp :: SourcePos }			-- ^ Lambda expressions have function type
	| SVApp		{ vsp :: SourcePos }			-- ^ LHS of an application must be a function
	| SVLiteral	{ vsp :: SourcePos, vLit :: LiteralFmt } -- ^ Literal values in expressions have distinct types
	| SVDoLast	{ vsp :: SourcePos }			-- ^ Do expressions have the type of the last stmt.
	| SVIfObj	{ vsp :: SourcePos }			-- ^ Match object of an if-expression must be Bool
	| SVProj	{ vsp :: SourcePos, vProj :: TProj }	-- ^ Value type constraints from field projection.
	| SVInst	{ vsp :: SourcePos, vVar :: Var }	-- ^ Type constraint from instance of this bound variable

	| SVLiteralMatch
			{ vsp :: SourcePos, vLit :: LiteralFmt } -- ^ Matching against a literal value.

	| SVMatchCtorArg
			{ vsp :: SourcePos } 			-- ^ Matching against a ctor gives types for its args.

	| SVSig		{ vsp :: SourcePos, vVar :: Var }	-- ^ Top level type signature.
	| SVSigClass	{ vsp :: SourcePos, vVar :: Var }	-- ^ Type signature in type-class dictionary definition.
	| SVSigExtern	{ vsp :: SourcePos, vVar :: Var }	-- ^ Type signature in a foreign import.
	| SVSigAnnot    { vsp :: SourcePos }                    -- ^ Constraint from a type annotation directly on an expression.

	| SVCtorDef	{ vsp :: SourcePos
			, vvarData :: Var
			, vvarCtor :: Var }			-- ^ Definition of constructor type.

	| SVCtorField	{ vsp :: SourcePos
			, vVarData :: Var
			, vVarCtor :: Var
			, vVarField :: Var }			-- ^ Type signature of constructor field.


	deriving (Show, Eq)


instance Pretty SourceValue PMode where
 ppr (SVInst sp v)	= parens $ "SVInst" %% sp %% v
 ppr sv			= "SV" %% vsp sv


-- | Sources of effect constraints
data SourceEffect
	= SEApp		{ esp :: SourcePos }			-- ^ Sum effects from application.
	| SEMatchObj	{ esp :: SourcePos }	 		-- ^ Effect from reading the match object.
	| SEMatch	{ esp :: SourcePos }			-- ^ Sum effects from match.
	| SEDo		{ esp :: SourcePos }			-- ^ Sum effects from do.
	| SEIfObj	{ esp :: SourcePos }			-- ^ Effect from reading the match object.
	| SEIf		{ esp :: SourcePos }			-- ^ Sum effects from if.
	| SEProj	{ esp :: SourcePos }			-- ^ Sum effects from projection.
	| SEGuardObj	{ esp :: SourcePos }			-- ^ Effect from reading the match object.
	| SEGuards	{ esp :: SourcePos }			-- ^ Sum effects from guards.
	deriving (Show, Eq)

instance Pretty SourceEffect PMode where
 ppr se		= "SE " % esp se


-- | Sources of closure constraints
data SourceClosure
	= SCApp		{ csp :: SourcePos }			-- ^ Sum closure from application.
	| SCLambda	{ csp :: SourcePos }			-- ^ lambda exprs bind their parameter var
	| SCMatch	{ csp :: SourcePos }			-- ^ Sum closure from match.
	| SCDo		{ csp :: SourcePos }			-- ^ Sum closure from do.
	| SCIf		{ csp :: SourcePos }			-- ^ Sum closure from if.
	| SCProj	{ csp :: SourcePos }			-- ^ Sum closure from projection.
	| SCGuards	{ csp :: SourcePos }			-- ^ Sum closure from guards.
	deriving (Show, Eq)

instance Pretty SourceClosure PMode where
 ppr sc		= "SE " % csp sc


-- | Sources of unification constraints
data SourceUnify
	= SUAltLeft	{ usp :: SourcePos }			-- ^ All LHS of case alternatives must have same type.
	| SUAltRight	{ usp :: SourcePos }			-- ^ All RHS of case alternatives must have same type.
	| SUIfAlt	{ usp :: SourcePos }			-- ^ All RHS of if expressions must have same type.
	| SUGuards	{ usp :: SourcePos }			-- ^ Unification of constraints placed on the match object by guards.
	| SUBind	{ usp :: SourcePos }			-- ^ LHS of binding has same type as RHS.
	deriving (Show, Eq)

instance Pretty SourceUnify PMode where
 ppr su		= "SU " % usp su


-- | Sources of other things (mostly to tag dictionaries)
data SourceMisc
	= SMGen		{ msp :: SourcePos, mVar :: Var }	-- ^ Used to tag source of generalisations due to let-bindings.
	| SMClassInst	{ msp :: SourcePos, mVar :: Var }	-- ^ Used to tag source of type-class instance dictionary definitions.
	| SMData	{ msp :: SourcePos } 			-- ^ Used to tag source of data definitions.
	| SMProjDict	{ msp :: SourcePos }			-- ^ Used to tag projection dictionaries.
	deriving (Show, Eq)


instance Pretty SourceMisc PMode where
 ppr sm		= "SM " % msp sm


-- | Sources of things added by the inferencer.
data SourceInfer
	-- | A name for an equivalence class invented by Type.Class.makeClassName
	= SIClassName

	-- | Used to tag const constraints arrising from purification of effects.
	| SIPurifier
		ClassId		-- the class holding that effect and purity constraint
		Effect 		-- the effect that was purified
		TypeSource	-- the source of the effect
		Fetter		-- the original purity fetter
		TypeSource	-- the source of this fetter

	-- ^ The result of crushing some fetter, also carrying typeSource information
	--	This is used when crushing things like Shape constraints, where the node
	--	in the graph is deleted after crushing, so we can't look it back up if
	--	we hit an error involving it.
	| SICrushedFS
		ClassId
		Fetter
		TypeSource

	-- ^ The result of crushing some effect
	| SICrushedES
		ClassId		-- the class holding the effect that was crushed
		Node		-- the effect that was crushed
		TypeSource	-- the source of this effect

	-- ^ A scheme that was generalised and added to the graph because its
	--	bound var was instantiated.
	| SIGenInst
		Var
		TypeSource

	deriving (Show, Eq)

instance Pretty SourceInfer PMode where
 ppr SIClassName		= ppr "SIClassName"

 ppr (SIPurifier cid eff effSrc f fSrc)
	= "SIPurifier" %% cid %% parens eff %% parens effSrc %% parens f %% parens fSrc

 ppr (SICrushedFS cid iF src)	= "SICrushedFS" %% cid %% parens iF %% src
 ppr (SICrushedES cid  iF src)	= "SICrushedES" %% cid %% parens iF %% src
 ppr (SIGenInst  v src)		= "SIGenInst "  %% v %% src


---------------------------------------------------------------------------------------------------
takeSourcePos :: TypeSource -> Maybe SourcePos
takeSourcePos ts
 = case ts of
 	TSV sv	-> Just $ vsp sv
	TSE se	-> Just $ esp se
	TSC sc	-> Just $ csp sc
	TSU su	-> Just $ usp su
	TSM sm	-> Just $ msp sm

	TSI (SICrushedFS _ _ src)	-> takeSourcePos src
	TSI (SICrushedES _ _ src)	-> takeSourcePos src
	TSI (SIPurifier  _ _ _ _ fSrc)	-> takeSourcePos fSrc
	TSI (SIGenInst   _ src)		-> takeSourcePos src

	_	-> Nothing


dispSourcePos :: TypeSource -> Str
dispSourcePos ts
 = case takeSourcePos ts of
 	Just sp	-> ppr sp
	Nothing	-> panic stage $ "dispSourcePos: no source location in " % ts


-- Display -----------------------------------------------------------------------------------------
-- | These are the long versions of source locations that are placed in error messages
dispTypeSource :: Pretty tt PMode => tt -> TypeSource -> Str
dispTypeSource tt ts
	| TSV sv	<- ts
	= dispSourceValue tt sv

	| TSE se	<- ts
	= dispSourceEffect tt se

	| TSU su	<- ts
	= dispSourceUnify tt su

	| TSI (SICrushedFS _ _ ts') <- ts
	= dispTypeSource tt ts'

	| TSI (SICrushedES _ eff effSrc) <- ts
	= dispTypeSource eff effSrc

	| otherwise
	= panic stage $ "dispTypeSource: no match for " % ts


-- | Show the source of a type error due to this reason
dispSourceValue :: Pretty tt PMode => tt -> SourceValue -> Str
dispSourceValue tt sv
 = case sv of
	SVLambda sp
		-> "lambda abstraction"
		%! "              at: " % sp

	SVApp sp
		-> "  function application"
		%! "              at: " % sp

	SVLiteral sp lit
	 	-> "  literal value "   % lit
		%! "         of type: " % tt
		%! "              at: " % sp

	SVDoLast sp
	 	-> "  result of do expression"
		%! "              at: " % sp

	SVIfObj sp
		-> "  object of if-then-else expression"
		%! "   which must be: Bool"
		%! "              at: " % sp

	SVProj sp j
	 -> let	cJ = case j of
	 		TJField v	-> TJField  v { varModuleId = ModuleIdNil }
	 		TJFieldR v	-> TJFieldR v { varModuleId = ModuleIdNil }
	 		TJIndex v	-> TJIndex  v { varModuleId = ModuleIdNil }
	 		TJIndexR v	-> TJIndexR v { varModuleId = ModuleIdNil }
	    in vcat
		[ "      projection '" % cJ % "'"
		, "         of type: " % tt
	 	, "              at: " % sp ]

	SVInst sp var
		-> "      the use of: " % var
		%! "         of type: " % tt
		%! "              at: " % sp

	SVLiteralMatch sp lit
		-> "  match against literal value " % lit
		%! "         of type: " % tt
		%! "              at: " % sp

	SVMatchCtorArg sp
		-> ppr "  argument of constructor match"
		%! "         of type: " % tt
		%! "              at: " % sp

	SVSig sp var
		-> "  type signature for '" % var % "'"
		%! "  which requires: " % tt
		%! "              at: " % sp

	SVSigClass sp var
		-> "  type signature for '" % var % "' in type-class definiton"
		%! "              at: " % sp

	SVSigExtern _ var
		-> "  type of import '" % var % "'"

	SVSigAnnot sp
		-> "  type annotation"
		%! "              at: " % sp

	SVCtorDef sp vData vCtor
		-> "  definition of constructor '" % vCtor % "' of '" % vData % "'"
		%! "              at: " % sp

	SVCtorField sp vData vCtor vField
		-> "  definition of field " % vField % " of '" % vCtor % "' in type '" % vData % "'"
		%! "              at: " % sp


-- | Show the source of a type error due to this reason
dispSourceEffect :: Pretty tt PMode => tt -> SourceEffect -> Str
dispSourceEffect tt se
 = case se of
	SEApp sp
		-> "  effect from function application"
		%! "          namely: " % tt
		%! "              at: " % sp

	SEMatchObj sp
		-> "  effect due to inspecting discriminant"
		%! "          namely: " % tt
		%! "              at: " % sp

	SEMatch sp
		-> "  effect of match alternative"
		%! "          namely: " % tt
		%! "              at: " % sp

	SEDo sp
		-> "  effect of do expression"
		%! "          namely: " % tt
		%! "              at: " % sp

	SEIfObj sp
		-> "  effect due to testing if-then-else discriminant"
		%! "              at: " % sp

	SEIf sp
		-> "  effect of if-then-else expression"
 		%! "          namely: " % tt
		%! "              at: " % sp

	SEProj sp
		-> "  effect of field projection"
		%! "          namely: " % tt
		%! "              at: " % sp

	SEGuardObj sp
		-> "  effect due to testing pattern guard"
		%! "          namely: " % tt
		%! "              at: " % sp

	SEGuards sp
		-> "  effect of pattern guards"
		%! "          namely: " % tt
		%! "              at: " % sp



-- | Show the source of a type error due to this reason
dispSourceUnify :: Pretty tt PMode => tt -> SourceUnify -> Str
dispSourceUnify tt sv
 = case sv of
 	SUAltLeft sp
		-> "alternatives"
		%! "              at: " % sp

	SUAltRight sp
		->  "result of alternatives"
		%! "              at: " % sp

	SUIfAlt sp
		-> "alternatives of if-then-else expression"
		%! "              at: " % sp

	SUGuards sp
		-> "match against pattern"
		%! "         at type: " % tt
		%! "              at: " % sp

	SUBind _
		-> ppr "binding"


-- Normalise ---------------------------------------------------------------------------------------
--	We don't want to display raw classIds in the error messages for two reasons
--
--	1) Don't want to worry the user about non-useful information.
--	2) They tend to change when we modify the type inferencer, and we don't want to
--		have to update all the check files for inferencer tests every time this happens.
--
-- Could do this directly on the string, if we displayed an * infront of type variables..


-- | Show the source of a fetter
--	This is used to print sources of class constraints when
--	we get a purity or mutability conflict.
--
--	The only possible source of these is instantiations of type schemes,
--	or from crushing other fetters.
--
dispFetterSource :: Fetter -> TypeSource -> Str
dispFetterSource f ts

	-- For purity constraints, don't bother displaying the entire effect
	--	purified, as most of it won't be in conflict.
	| FConstraint v _	<- f
	, v == primPure
	, TSV (SVInst sp var)	<- ts
	=  "      the use of: " % var
	%! "              at: " % sp

	| FConstraint _ _	<- f
	, TSV (SVInst sp var)	<- ts
	=  "      constraint: " % f
	%! " from the use of: " % var
	%! "              at: " % sp

	| TSV (SVInst sp var)	<- ts
	= "      constraint: " % f
	%! " from the use of: " % var
	%! "              at: " % sp

	| TSV (SVSig  sp var) 	<- ts
	= "      constraint: " % f
	%! " in type sig for: " % var
	%! "              at: " % sp

	| FConstraint _ _	<- f
	, TSI (SICrushedFS _ f' src)	<- ts
	= dispFetterSource f' src

	| FConstraint _ _				<- f
	, TSI (SIPurifier _ eff effSrc fPure fPureSrc)	<- ts
	=  "      constraint: " % f
	%! "which purifies"
	%! dispTypeSource   eff effSrc
	%! "due to"
	%! dispFetterSource fPure fPureSrc

	-- hrm.. this shouldn't happen
	| otherwise
	= panic stage $ "dispFetterSource: no match for " % show ts

