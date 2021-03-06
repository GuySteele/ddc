
module Source.DefixApps
	(defixApps)
where
import Shared.Warning
import Source.Exp
import Source.Pretty		()
import DDC.Main.Pretty
import DDC.Main.Error
import DDC.Var
import qualified Shared.VarPrim	as Var

-----
stage	= "Source.DefixApps"

-- | Takes the list of expressions from inside an $XDefix and
--   builds (suspended) function applications.
defixApps ::	Pretty a PMode => a -> [Exp a] -> [Exp a]
defixApps	sp xx
	= rewriteApps $ dropApps sp xx

-- Takes a list of expressions from inside an $XDefix and wraps runs of exps that
--   lie between between (non-@) infix operators in $XDefixApps. This is the first
--   step in defixing process.
--
--   eg  [f, x, @, a, b, +, g, y, -, h, @, 5]
--
--   =>  [$XDefixApps [f, x, @, a, b], +, $XDefixApps [g, y], -, XDefixApps [h, @, 5]]
--
dropApps :: 	Pretty a PMode => a -> [Exp a] -> [Exp a]
dropApps sp es

	-- Special case of variable followed by a binary opertor and nothing
	-- else. Return them with swapped order so the operator acts as a
	-- function on the variable.
	| x1 : x2@XOp{} : []		<- es
	= [ x2, x1 ]

	-- Check if the expression starts with a unary minus
	--	- x + 5   parses as  (negate x) + 5
	| XOp sp v : e2 : esRest	<- es
	, varName v == "-"
	= dropApps' sp [XApp sp (XVar sp Var.primNegate) e2] esRest

	| otherwise
	= dropApps' sp [] es

-- Collect up pieces of applications in the accumualtor a1 a2 a3
dropApps' sp acc []
	= [makeXDefixApps sp acc]

dropApps' sp acc xx
	-- Chop out the unary minus if we see two ops in a row
	--	x1 += - f x 	parses as   x1 += (- (f x))
	| x1@(XOp sp1 v1) : x2@(XOp sp2 v2) : xsRest	<- xx
	, varName v2 == "-"
	= makeXDefixApps sp acc : x1
	: dropApps' sp [XVar sp Var.primNegate] xsRest

 	| x@(XOp sp v) : xs				<- xx
	, varName v == "$"
        , null acc
	= dropApps' sp acc $ warning (WarnRedundantOp v) xs

	-- when we hit a non '@' operator, mark the parts in the accumulator
	--	as an application and start collecting again.
 	| x@(XOp sp v) : xs				<- xx
	, varName v /= "@"
	= makeXDefixApps sp acc : x : dropApps' sp [] xs

	| x : xs	<- xx
	= dropApps' sp (acc ++ [x]) xs

makeXDefixApps sp xx
 = case xx of
	-- If we hit two operators in a row, and the second one isn't unary
	--	minus then we'll get an empty list here. eg  x + + 1
	[]	-> panic stage
			$ "makeXDefixApps: parse error at\n" % sp
			% "   xx = " % xx	% "\n"
	[x]	-> x
	_	-> XDefixApps sp xx


-- Takes a list of expressions and converts $XDefixApp nodes into XApp nodes.
--   Also converts @ operators into explicit calls to the suspend functions.
--   eg [f, x, @, a, b, @, c, d, e]
--	=> suspend3 (suspend2 (f x) a b) c d e
rewriteApps ::	[Exp a] -> [Exp a]
rewriteApps	[]	= []
rewriteApps	(x:xs)
 = case x of
 	XDefixApps sp xx
	 -> rewriteApp sp xx : rewriteApps xs

	_ -> x : rewriteApps xs


rewriteApp :: 	a -> [Exp a] -> (Exp a)
rewriteApp	sp es
	= rewriteApp' sp [] es

rewriteApp' sp left []
 	= unflattenApps sp left

rewriteApp' sp left (x:xs)
 = case x of
 	XOp sp op

	 -- If dropApps is working properly then we shouldn't find
	 --	any non-@ operators at this level.
	 |  varName op /= "@"
 	 -> panic stage "rewriteApp: found non-@ operator."

	 |  otherwise
	 -> let (bits, rest)	= takeUntilXOp [] xs
		args		= length bits

		suspV		= Var.primSuspend args
		susp		= suspV
				{ varInfo 		= (varInfo suspV) ++ (varInfo op) }

		leftApp		= unflattenApps sp left
		app		= unflattenApps sp (XVar sp susp : leftApp : bits)

	   in	rewriteApp' sp [app] rest

	_ -> rewriteApp' sp (left ++ [x]) xs


takeUntilXOp acc []	= (acc, [])
takeUntilXOp acc (x:xs)
 = case x of
 	XOp{}		-> (acc, x:xs)
	_		-> takeUntilXOp (acc ++ [x]) xs

unflattenApps :: a -> [Exp a] -> (Exp a)
unflattenApps	sp [x]	= x
unflattenApps  	sp xx
 = unflattenApps' sp $ reverse xx

unflattenApps' sp xx
 = case xx of
	(x1:x2:[])	-> XApp sp x2 x1
 	(x:xs)		-> XApp sp (unflattenApps' sp xs) x



