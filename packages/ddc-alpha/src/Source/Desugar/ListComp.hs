
module Source.Desugar.ListComp
	(rewriteListComp)
where
import Util
import Shared.VarPrim
import Source.Desugar
import Source.Desugar.Base
import Source.Desugar.Patterns
import DDC.Base.SourcePos
import DDC.Main.Error
import DDC.Main.Pretty
import DDC.Var
import qualified DDC.Var.PrimId		as Var
import qualified Source.Exp		as S
import qualified DDC.Desugar.Exp	as D

stage = "Source.Desugar.ListComp"

-----
-- rewriteListComp
--	Expand out a list comprehension.
--	ala Section 3.11 of the Haskell 98 report.
--
--	BUGS: let patterns not implemented yet.
--
rewriteListComp
	:: S.Exp SourcePos -> RewriteM (D.Exp Annot)

rewriteListComp x
 = case x of

	-- [ e | True ] 		=> [e]
 	S.XListComp sp exp [S.LCExp (S.XVar _ v)]
	 |  varId v == VarIdPrim Var.VTrue
	 -> do	exp'	<- rewrite exp
		let ann	= annotOfSp sp
	 	return 	$ D.XApp ann (D.XApp ann (D.XVar ann primCons) exp') (D.XVar ann primNil)

	-- [ e | q ]			=> [e | q, True]
	S.XListComp sp exp [q]
	 -> rewriteListComp
	 		$ S.XListComp sp exp [q, S.LCExp (S.XVar sp primTrue)]

	-- [ e | b, Q ]			=> if b then [e | Q] else []
	S.XListComp sp exp (S.LCExp b : qs)
	 -> do	lc'	<- rewriteListComp $ S.XListComp sp exp qs
		b'	<- rewrite b
		let ann	 = annotOfSp sp
	 	return 	$ D.XIfThenElse ann b' lc' (D.XVar ann primNil)

	-- [ e | p <- l, Q]		=> let ok p = [e | Q] in concatMap ok l
	S.XListComp sp exp (S.LCGen lazy (S.WVar _ p) l : qs)
	 -> do	let catMapVar	= if lazy then primConcatMapL else primConcatMap;
		lc'	<- rewriteListComp $ S.XListComp sp exp qs
		l'	<- rewrite l
		let ann	 = annotOfSp sp
	 	return	$ D.XDo ann
				[ D.SBind ann Nothing  (D.XApp ann (D.XApp ann (D.XVar ann catMapVar) (D.XLambda ann p lc') ) l') ]

	-- [e | pattern <- l, Q]		=> concatMap (\p -> case p of pattern -> [e | Q]; _ -> []) l
	S.XListComp sp exp (S.LCGen lazy pat l : qs)
	 -> do	let catMapVar	= if lazy then primConcatMapL else primConcatMap

		lc'	<- rewriteListComp $ S.XListComp sp exp qs
		l'	<- rewrite l
		pat'	<- rewrite [pat]
		let ann	 = annotOfSp sp

		patFunc	<- makeMatchFunction sp pat' lc' (Just (D.XVar ann primNil))

	 	return	$ D.XDo ann
				[ D.SBind ann Nothing  (D.XApp ann (D.XApp ann (D.XVar ann catMapVar) patFunc) l') ]

	-- [e | let s, Q]		=> let s in [e | Q]
	S.XListComp sp exp (S.LCLet ss : qs)
	 -> do	lc'	<- rewriteListComp $ S.XListComp sp exp qs
		rewriteLetStmts sp ss lc'

	_ -> panic stage
		$ pprStrPlain $ "rewriteListComp failed for\n    " % x % "\n"

