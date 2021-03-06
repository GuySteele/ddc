{-# OPTIONS -fwarn-incomplete-patterns #-}

-- | Pretty printer for Source.Exp expressions.
module Source.Pretty
	()
where
import Util
import Source.Exp
import Source.Horror
import DDC.Main.Pretty
import DDC.Main.Error
import DDC.Type
import DDC.Var
import Data.Char		(isAlpha)

stage	= "Source.Pretty"

-- Top ---------------------------------------------------------------------------------------------
instance Pretty (Top a) PMode where
 ppr xx
  = case xx of
	PPragma _ es
	 -> "pragma " % " " %!% es % ";"

	PModule _ v
	 -> "module " % v % ";"

	PImportModule _ [m]
	 -> "import " % m % ";"

	PImportModule _ ms
	 -> pprHeadBlock "import " ms

	PExport _ xx
	 -> pprHeadBlock "export " xx

	PForeign _ f
	 -> "foreign " % f % ";"

	PKindSig sp v k
	 | resultKind k == kValue
	 -> "data" 	%% v %>> " :: " % k % ";"

	 | resultKind k == kEffect
	 -> "effect" 	%% v %>> " :: " % k % ";"

	 | otherwise
	 -> "type" 	%% v %>> " :: " % k % ";"

	PTypeSynonym sp v t
         -> "type" 	%% v %>> " = " % prettyTypeSplit t % ";"

	PData _ typeName vars []
	 -> "data" 	%% punc " " (typeName : vars) % ";"

	PData _ typeName vars ctors
	 -> "data " 	%% punc " " (typeName : vars) % nl
			%> "= "  % punc (nlnl %% "| ") (map ppr ctors) % ";"

	PRegion _ v
	 -> "region " % v % ";"

	PClass _ v k
	 -> "class " % v %>> " :: " % k % ";"

	PClassDict _ c vks inh sigs
	 -> pprHeadBlock ("class "	% c % " " % (punc " " $ map pprPClass_vk vks)    % " where" % nl)
	  $ [punc ", " vs %% ":: " %> prettyTypeSplit t | (vs, t) <- sigs]

	PClassInst _ v ts inh ss
	 -> pprHeadBlock ("instance "	% v % " " % (punc " " $ map prettyTypeParens ts) % " where" % nl)
	  	(map 	(\s -> case s of
				SBindFun sp v pats alts
				  -> ppr $ SBindFun sp v pats alts
				_ -> panic stage $ "pretty[Top]: malformed PClassInst\n")
			ss)

	PProjDict _ t ss
	 -> pprHeadBlock ("project " % t % " where" % nl) ss

	PStmt s
	 -> ppr s

	PInfix _ mode prec syms
	 -> mode % " " % prec %% ", " %!% (map infixNames syms) % " ;"

infixNames v
 = if isAlpha (head (varName v))
	then "`" ++ varName v ++ "`"
	else varName v

pprPClass_vk :: (Var, Kind) -> Str
pprPClass_vk (v, k)
 	| elem k [kValue, kRegion, kEffect, kClosure]
	= ppr v

	| otherwise
	= parens $ v %% "::" %% k


-- CtorDef ----------------------------------------------------------------------------------------
instance Pretty (CtorDef a) PMode where
 ppr CtorDef
	{ ctorDefName	= name
	, ctorDefFields	= fields }
  = case fields of
 	[] -> ppr name
	fs -> name 	%% "{" % nl
			%> (nl %!% (map pprStrPlain fs)) % nl
			%  "}"

-- DataField --------------------------------------------------------------------------------------
instance Pretty (DataField a) PMode where
 ppr DataField
	{ dataFieldLabel	= Nothing
	, dataFieldType		= t }
	= t % ";"

 ppr DataField
	{ dataFieldLabel	= mLabel
	, dataFieldType		= t }
	= fromMaybe (ppr " ") (liftM ppr mLabel)
	%> (" :: " % t)


-- Export ------------------------------------------------------------------------------------------
instance Pretty (Export a) PMode where
 ppr ex
  = case ex of
	EValue _ v	-> ppr v
	EType _ v	-> "type"   %% v
	ERegion _ v	-> "region" %% v
	EEffect _ v	-> "effect" %% v
	EClass _ v	-> "class"  %% v


-- Foreign -----------------------------------------------------------------------------------------
instance Pretty (Foreign a) PMode where
 ppr ff
  = case ff of
 	OImport mS v tv mTo
	 -> let pName	= case mS of  { Nothing -> ppr " "; Just s  -> ppr $ show s }
		pTo	= case mTo of { Nothing -> ppr " "; Just to -> nl % ":$" %% to }
	    in
		"import "
			%  pName % nl
			%% v 	 %> (nl %% "::" %% prettyTypeSplit tv  % pTo)

	OImportUnboxedData name var knd
	 -> "import data" %% show name %% var %% "::" %% knd


-- InfixMode ---------------------------------------------------------------------------------------
instance Pretty (InfixMode a) PMode where
 ppr mode
  = case mode of
 	InfixLeft	-> ppr "infixl"
	InfixRight	-> ppr "infixr"
	InfixNone	-> ppr "infix "
	InfixSuspend	-> ppr "@InfixSuspend"


-- Exp ---------------------------------------------------------------------------------------------
instance Pretty (Exp a) PMode where
 ppr xx
  = case xx of
  	XNil		-> ppr "@XNil"
  	XType	sp e t	-> "(" % e % "::" % t % ")"
	XLit 	sp c	-> ppr c
	XVar 	sp v	-> ppr v

	XProj 	sp x p
	 -> prettyXB x % p

	XProjT 	sp t p
	 -> "@XProjT " % prettyTypeParens t % " " % p

	XLet 	sp ss e
	 -> pprHeadBlock "let" ss %% "in" %% e

	XDo 	sp ss
	 -> pprHeadBlock "do" ss

	XWhere  sp xx ss
	 -> xx % pprHeadBlock "where" ss

	XCase 	sp co ca
	 -> pprHeadBlock ("case" %% co %% "of ") ca

	XLambdaPats sp ps e
	 -> "\\" % " " %!% ps % " -> " % e

	XLambdaProj sp j xs
	 -> "\\" % j % " " % (punc " " $ map prettyXB xs)

	XLambdaCase sp cs
	 -> "\\case {" % nl
	 	%> vsep (map ppr cs)
		%  nl % "}"

	XApp 	sp e1 e2
	 -> if orf e1 [isXVar, isXApp]

	 	then e1 % " " % prettyXB e2

		else "(" % e1 % ")\n" %> prettyXB e2


	XIfThenElse sp e1 e2 e3
	 ->  "if " % (if isEBlock e1 then "\n" else " ") % e1
		%> ("\nthen " 	% (if isEBlock e2 then "\n" else " ") % e2)

		% (if isEBlock e2 then "\n" else " ")
		%> ("\nelse "	% (if isEBlock e3 then "\n" else " ") % e3)

	-- object expressions
	XObjField 	sp v	-> "_" % v

	-- infix expressions
	XOp 		sp v	 -> "@XOp " % v
	XDefix 		sp es	 -> "@XDefix " % es
 	XDefixApps 	sp es	 -> "@XDefixApps " % es
	XAppSusp	sp x1 x2 -> "@XAppSusp " % x1 %% x2

	-- constructor sugar
	XTuple sp xx		-> "(" % ", " %!% xx % ")"
	XList  sp xx		-> "[" % ", " %!% xx % "]"

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
	 %> ("\n\n" %!% aa)
	 %  "\n}\n"
	 %  "with " % wX % ";"

	XThrow sp x
	 -> "throw " % x

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
	XListRange sp b x Nothing Nothing	-> "[" % x % "..]"
	XListRange sp b x Nothing (Just x2)	-> "[" % x % " .. " % x2 % "]"
	XListRange sp b x (Just x1) Nothing	-> "[" % x % ", " % x1 % "..]"
	XListRange sp b x (Just x1) (Just x2)	-> "[" % x % ", " % x1 % " .. " % x2 % "]"

	XListComp sp x qs 		-> "[" % x % " | " % ", " %!% qs % "]"

	-- parser helpers
	XParens a x		-> "@XParens " % x

-- Proj --------------------------------------------------------------------------------------------
instance Pretty (Proj a) PMode where
 ppr f
  = case f of
  	JField  sp l	-> "." % l
	JFieldR sp l	-> "#" % l

	JIndex	sp x	-> ".(" % x % ")"
	JIndexR	sp x	-> "#(" % x % ")"

-----
isEBlock x
	= orf x	[ isXLet
		, isXCase
		, isXDo ]

prettyXB xx
 = case xx of
 	XVar sp v	-> ppr v
	XLit sp c	-> ppr c
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


-- Alt ---------------------------------------------------------------------------------------------
instance Pretty (Alt a) PMode where
 ppr a
  = case a of
	APat 	 sp p1 x2	-> p1	% "\n -> " % prettyX_naked x2 % ";"

	AAlt	 sp [] x	-> "\\= " % x % ";"
	AAlt	 sp gs x	-> "|"  % "\n," %!% gs % "\n=  " % x % ";"

	ADefault sp x		-> "_ ->" % x % "\n"


-- Guard -------------------------------------------------------------------------------------------
instance Pretty (Guard a) PMode where
 ppr gg
  = case gg of
	GExp	sp pat exp	-> " "  % pat %>> " <- " % exp
	GBool	sp exp		-> " "  % ppr exp


-- Pat ---------------------------------------------------------------------------------------------
instance Pretty (Pat a) PMode where
 ppr ww
  = case ww of
  	WVar 	sp v		-> ppr v
	WObjVar	sp v		-> "^" % v
	WLit 	sp c		-> ppr c
	WCon 	sp v ps		-> (punc " " $ ppr v : map prettyWB ps)
	WConLabel sp v lvs	-> v % " { " % ", " %!% map (\(l, v) -> l % " = " % v ) lvs % "}"
	WAt 	sp v w		-> v % "@" % prettyWB w
	WWildcard sp 		-> ppr "_"
	WUnit	sp		-> ppr "()"
	WTuple  sp ls		-> "(" % ", " %!% ls % ")"
	WCons   sp x xs		-> prettyWB x % " : " % xs
	WList   sp ls		-> "[" % ", " %!% ls % "]"

prettyWB ww
 = case ww of
 	WVar{}			-> ppr ww
	WObjVar{}		-> ppr ww
	WLit{}			-> ppr ww
	WCon 	sp v []		-> ppr ww
	WConLabel{}		-> ppr ww
	WAt{}			-> ppr ww
	WWildcard{}		-> ppr ww
	WUnit{}			-> ppr ww
	WTuple{}		-> ppr ww
	WCons{}			-> parens (ppr ww)
	WList{}			-> ppr ww
	_			-> parens (ppr ww)

-- Label -------------------------------------------------------------------------------------------
instance Pretty (Label a) PMode where
 ppr ll
  = case ll of
  	LIndex sp i		-> "." % i
	LVar   sp v		-> ppr v


-- LCQual ------------------------------------------------------------------------------------------
instance Pretty (LCQual a) PMode where
 ppr q
  = case q of
  	LCGen False p x	-> p % " <- " % x
	LCGen True  p x -> p % " <@- " % x
	LCExp x		-> ppr x
	LCLet ss	-> "let {\n"
				%> ";\n" %!% ss
				%  "\n}"


-- Stmt --------------------------------------------------------------------------------------------
instance Pretty (Stmt a) PMode where
 ppr xx
  = case xx of
	SSig sp sigMode v t
	 -> v %> " " % sigMode %% t

	SStmt sp  x
	 -> prettyX_naked x

	SBindFun sp v [] [ADefault _ x]
	 -> padL 8 v % " "
	 	%>> spaceDown x	% " = " % prettyX_naked x

	SBindFun sp v ps [ADefault _ x]
	 -> v % " " % punc " " (map prettyWB ps)
	  	%>> spaceDown x % " = " % prettyX_naked x

	SBindFun sp v pats alts
	 -> v % " " % punc " " (map prettyWB pats) % " {\n"
	  	%> ("\n\n" %!% alts)
	  	%  "\n}"

	SBindPat sp pat x
	 -> pat %>> spaceDown x % " = " % prettyX_naked x

	SBindMonadic sp v x
	 -> v %% "<-" %% x


spaceDown xx
 = case xx of
	XLambdaCase{}	-> newline
 	XCase{}		-> newline
	XIfThenElse{}	-> newline
	XDo{}		-> newline
	_		-> blank


