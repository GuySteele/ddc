{-# OPTIONS -fwarn-incomplete-patterns #-}

-----
-- Source.Pretty
--
-- Summary:
--	Pretty printer for Source.Exp expressions.
--	Must keep output format parseable by trauma parser.
--
--
module Source.Pretty
	()
where

-----
import Util

-----
import Util.Pretty

-----
import qualified Shared.Var 	as Var
import Shared.Error

import Source.Exp
import Source.Horror
import Source.Util
import Shared.Pretty

import Type.Pretty

-----
stage	= "Source.Pretty"

-----
-- prettyTop
--
instance Pretty Top where
 ppr xx
  = case xx of
	PPragma es	 -> "pragma " % " " %!% es % ";\n"
	PModule v	 -> "module " % v % ";\n"

	PImportExtern  v tv to
	 -> "import extern " % prettyVTT v tv to % "\n"

	PImportModule [m] -> "import " % m % ";\n"
	
	PImportModule xx
	 -> "import " 
		% "{\n"
			%> "\n" %!% map (\x -> x % ";") xx
		% "\n}\n\n"
		
	PForeign f 
	 -> "foreign " % f % ";\n\n"
	
	PData typeName vars [] 
	 -> "data " % " " %!% (typeName : vars) % ";\n\n"

	PData typeName vars ctors
	 -> "data " % " " %!% (typeName : vars) % "\n"
		%> ("= "  % "\n\n| " %!% (map prettyCtor ctors) % ";")
		%  "\n\n"

	PRegion v	 -> "region " % v % ";\n"
	PEffect v k	 -> "effect " % v %>> " :: " % k % ";\n"

	-- Classes
	PClass v k	 -> "class " % v %>> " :: " % k % ";\n"

	PClassDict c vs inh sigs
	 -> "class " % c % " " % (" " %!% vs) % " where\n"
		% "{\n"
	 	%> ("\n\n" %!% 
			(map (\(vs, t) -> ", " %!% 
				(map (\v -> v { Var.nameModule = Var.ModuleNil }) vs)
				% " :: " %> prettyTypeSplit t % ";") sigs)) % "\n"
		% "}\n\n"

	PClassInst v ts inh ss
	 -> "instance " % v % " " % " " %!% (map prettyTB ts) % " where\n"
		% "{\n"
		%> ("\n\n" %!% 
			(map 	(\s -> case s of 
					SBind sp (Just v) x 
					 -> pprStr $ SBind sp (Just v { Var.nameModule = Var.ModuleNil }) x

					SBindPats sp v xs x
					 -> pprStr $ SBindPats sp (v { Var.nameModule = Var.ModuleNil }) xs x)

				ss)
			% "\n")
		% "}\n\n"

	-- Projections
	PProjDict t ss
	 -> "project " % t % " where\n"
		% "{\n"
		%> ("\n\n" %!% ss) % "\n"
		% "}\n\n"
	 

	-- type sigs	 
	PType sp v t
         -> v %>> " :: " % prettyTS t % ";\n"
	 

	PStmt s		 -> ppr s % "\n\n"
	
	PInfix mode prec syms
	 -> mode % " " % prec % " " % ", " %!% (map Var.name syms) % " ;\n"


prettyVTT ::	Var -> 	Type -> Maybe Type	-> PrettyP
prettyVTT   	v	tv	mto
	=  v 	% "\n"
			%> (":: " % prettyTS tv % "\n" 
			% case mto of 
				Nothing	-> ppr ""
				Just to	-> ":$ " % to % "\n")


prettyCtor ::	(Var, [DataField Exp Type])	-> PrettyP
prettyCtor	xx
 = case xx of
 	(v, [])		-> ppr v
	(v, fs)		
	 -> v % " {\n"
		%> ("\n" %!% (map pprStr fs)) % "\n"
		% "}"
-----
-- Foreign
--
instance Pretty Foreign where
 ppr ff
  = case ff of
  	OImport f		-> "import " % f
	OExport f		-> "export " % f
	
	OExtern mS v tv mTo
	 -> let pName	= case mS of  { Nothing -> ppr " "; Just s  -> ppr $ show s }
		pTo	= case mTo of { Nothing -> ppr " "; Just to -> "\n:$ " % to }
	    in 
	 	"extern " % pName % "\n " 
		 % v 	%> ("\n:: " % prettyTS tv 	% pTo)

	OCCall mS v tv 
	 -> ppr "@CCall"

-----
-- InfixMode
--
instance Pretty InfixMode where
 ppr mode
  = case mode of
 	InfixLeft	-> ppr "infixl"
	InfixRight	-> ppr "infixr"
	InfixNone	-> ppr "infix "
	InfixSuspend	-> ppr "@InfixSuspend"
	
-----
-- Exp
--
instance Pretty Exp where
 ppr xx
  = case xx of
  	XNil		 -> ppr "@XNil"
	XAnnot aa e	 -> aa % prettyXB e

	XUnit sp	 -> ppr "()"

	XVoid	sp	 -> ppr "_"
	XConst 	sp c	 -> ppr c

	XVar 	sp v	 -> ppr v

	XProj 	sp x p	 -> prettyXB x % p
	XProjT 	sp t p	 -> "@XProjT " % prettyTB t % " " % p


	XLambda sp v e	 -> "\\" % v % " -> " % e


	XLet 	sp ss e
	 -> "let {\n" 
		%> ";\n" %!% ss
		%  "\n} in " % e

	XDo 	sp ss	 -> "do {\n" %> "\n" %!% ss % "\n}"

	XCase 	sp co ca
	 -> "case " % co % " of {\n" 
	 	%> "\n\n" %!% ca
		%  "\n}"

	XLambdaPats sp ps e
	 -> "\\" % " " %!% ps % " -> " % e

	XLambdaProj sp j xs
	 -> "\\" % j % " " % xs

	XLambdaCase sp cs
	 -> "\\case {\n"
	 	%> "\n\n" %!% cs
		%  "\n}"

	XCaseE 	sp co ca eff
	 -> "case " % co % " of " % eff % " {\n" 
	 	%> "\n\n" %!% ca
		%  "\n}"

	XApp 	sp e1 e2
	 -> if orf e1 [isXVar, isXApp, isXAnnot, isXUnit]

	 	then e1 % " " % prettyXB e2

		else "(" % e1 % ")\n" %> prettyXB e2
		
 
	XIfThenElse sp e1 e2 e3
	 ->  "if " % (if isEBlock e1 then "\n" else " ") % e1 
		%> ("\nthen " 	% (if isEBlock e2 then "\n" else " ") % e2)

		% (if isEBlock e2 then "\n" else " ")
		%> ("\nelse "	% (if isEBlock e3 then "\n" else " ") % e3)

	-----
	XAt 	sp v exp	 -> v % "@" % prettyXB exp

	-- object expressions
	XObjVar 	sp v	 -> "^" % v
	XObjField 	sp v	 -> "_" % v

	-- infix expressions
	XOp 		sp v	 -> "@XOp " % v
	XDefix 		sp es	 -> "@XDefix " % es
 	XDefixApps 	sp es	 -> "@XDefixApps " % es

	-- lambda sugar


	-- match sugar
	XMatch sp aa	
	 -> "match {\n" 
	 	%> "\n\n" %!% aa
		%  "\n}"
	
	-- exception sugar
	XTry sp x aa Nothing
	 -> "try " % prettyXB x % "\n"
	 %  "catch {\n" 
	 %> ("\n" %!% aa)
	 %  "};"

	XTry sp x aa (Just wX)
	 -> "try " % prettyXB x % "\n"
	 %  "catch {\n" 
	 %> ("\n" %!% aa)
	 %  "}\n"
	 %  "with " % wX % ";"

	-- imperative sugar
	XWhile sp x1 x2
	 -> "while (" % x1 % ")\n"
	 % x2
	 
	XWhen sp x1 x2
	 -> "when (" % x1 % ")\n"
	 % x2
	 
	XUnless sp x1 x2
	 -> "unless (" % x1 % ")\n"
	 % x2
	
	XBreak sp 
	 -> ppr "break"
	 
	-- list range sugar
	XListRange sp b x Nothing		-> "[" % x % "..]"
	XListRange sp b x (Just x2)	-> "[" % x % ".." % x2 % "]"
	
	
	XListComp sp x qs 		-> "[" % x % " | " % ", " %!% qs % "]"
	

	-- patterns
	XCon   sp v xx			-> v % " " % " " %!% xx
	XTuple sp xx			-> "(" % ", " %!% xx % ")"
	XCons  sp x1 x2			-> x1 % ":" % x2
	XList  sp xx			-> "[" % ", " %!% xx % "]"

	_ 	-> panic stage
		$  "pprStr[Exp]: not match for " % show xx

instance Pretty Proj where
 ppr f
  = case f of
  	JField  l	-> "." % l
	JFieldR l	-> "#" % l

	JIndex	x	-> ".[" % x % "]"
	JIndexR	x	-> "#[" % x % "]"

	JAttr	v	-> ".{" % v % "}"

-----
isEBlock x
	= orf x	[ isXLet 
		, isXCase
		, isXDo ]
	
prettyXB xx
 = case xx of
 	XVar sp v	-> ppr v
	XConst sp c	-> ppr c
	XUnit sp	-> ppr xx
	XProj{}		-> ppr xx
	e		-> "(" % e % ")"
	
prettyX_naked xx
 = case xx of
	XApp sp e1 e2	-> prettyX_appL (XApp sp e1 e2)
	e		-> ppr e


prettyX_appL xx
 = case xx of
	XApp sp e1 e2
	 -> prettyX_appL e1 
		%  " "
		% prettyX_appR e2

	e  -> prettyXB e


-----
prettyX_appR xx
 = case xx of
	XApp sp e1 e2	->  "(" % prettyX_appL e1 % " " % prettyX_appR e2 % ")"
	e 		-> prettyXB e

-----
instance Pretty Annot where
 ppr xx 
  = case xx of
  	ATypeVar   v	-> "@T " % v
	AEffectVar v	-> "@E " % v

-----
instance Pretty Alt where
 ppr a
  = case a of
	APat 	 p1 x2		-> p1	% "\n -> " % prettyX_naked x2 % ";"

	AAlt	 [] x		-> "\\= " % x % ";"
	AAlt	 gs x		-> "|"  % "\n," %!% gs % "\n=  " % x % ";"

	ADefault x		-> "_ ->" % x % "\n"
	

instance Pretty Guard where
 ppr gg
  = case gg of
  	GCase pat		-> "- " % pat
	GExp  pat exp		-> " "  % pat %>> " <- " % exp
	GBool exp		-> " "  % ppr exp
	GBoolU exp		-> "# " % exp
	
instance Pretty Pat where
 ppr ww
  = case ww of
  	WVar v			-> ppr v
	WConst c		-> ppr c
	WCon v ps		-> v % " " % ps %!% " " 
	WConLabel v lvs		-> v % " { " % ", " %!% map (\(l, v) -> l % " = " % v ) lvs % "}"
	WAt v w			-> v % "@" % w
	WWildcard 		-> ppr "_"
	WExp x			-> ppr x

instance Pretty Label where
 ppr ll
  = case ll of
  	LIndex i		-> "." % i
	LVar   v		-> "." % v

-----
instance Pretty LCQual where
 ppr q
  = case q of
  	LCGen False p x	-> p % " <- " % x
	LCGen True  p x -> p % " <@- " % x
	LCExp x		-> ppr x
	LCLet ss	-> "let { " % ss % "}"

-----
instance Pretty Stmt where
 ppr xx
  = case xx of
	SBind sp Nothing x	-> prettyX_naked x 					% ";"
	SBind sp (Just v) x	-> v 			%>> (spaceDown x) % " = " % prettyX_naked x 	% ";"

	SBindPats sp v [] x	-> v % " " 		%>> (spaceDown x) % " = " % prettyX_naked x 	% ";"
	SBindPats sp v ps x	
		-> v % " " % " " %!% map prettyXB ps 
		%>> (spaceDown x) % "\n = " % prettyX_naked x 	% ";"


	SSig sp v t		-> v %> " :: " % t % ";"

spaceDown xx
 = case xx of
	XLambda{}	-> ppr "\n"
	XLambdaCase{}	-> ppr "\n"
 	XCase{}		-> ppr "\n"
	XCaseE{}	-> ppr "\n"
	XIfThenElse{}	-> ppr "\n"
	XDo{}		-> ppr "\n"
	_		-> pNil


-- instance Pretty FixDef where
--  pprStr	= prettyFD

prettyFD :: 	FixDef -> String
prettyFD 	(v, (fixity, mode))
	= pprStr mode ++ " " ++ show fixity ++ " " ++ Var.name v ++ " ;"
	


