
-- | 	Snip out function applications and compound expressions from function arguments.
--	This needs to be run after Core.Block, which wraps the applications of interest in XDos.
module Core.Snip
	( Table(..)
	, snipGlob )
where
import Core.Util
import Core.Plate.Trans
import Util
import DDC.Main.Pretty
import DDC.Core.Exp
import DDC.Core.Glob
import DDC.Core.Check
import DDC.Type
import DDC.Var
import DDC.Var.PrimId
import Shared.VarGen			(VarGenM, newVarN)
import qualified Data.Map		as Map
import qualified Debug.Trace

stage		= "Core.Snip"
debug 		= False
trace s	x 	= if debug then Debug.Trace.trace (pprStrPlain s) x else x

-- Snipper Monad ----------------------------------------------------------------------------------
type SnipM	= VarGenM

-- | Snipper environment.
data Table
	= Table
	{  -- | Globs used to determine which variable are defined at top level.
	   tableHeaderGlob	:: Glob
	,  tableModuleGlob	:: Glob

	   -- | whether to preserve type information of snipped vars
  	   --	  this requires that expressions have locally reconstuctable types
	,  tablePreserveTypes	:: Bool }


-- Snip -------------------------------------------------------------------------------------------
-- | Snip bindings in this tree.
snipGlob
	:: Table
	-> String	-- string to use for var prefix
	-> Glob 	-- ^ Glob to snip.
	-> Glob		-- ^ Snipped Glob.

snipGlob table varPrefix glob
 = let	transTable	= transTableId { transSS = snipStmts table }
	glob'		= evalState
			 	(mapBindsOfGlobM (transZM transTable) glob)
				$ VarId varPrefix 0
   in	glob'


-- | Keep running the snipper on these statements until nothing more will snip.
snipStmts ::	Table -> [Stmt] -> SnipM [Stmt]
snipStmts	table ss
 = do
	ss'	<- snipPass table ss

	if length ss == length ss'
	 then return ss'
	 else snipStmts table ss'


-- | Run one snipper pass on this list of statements.
--	Any new stmts are placed infront of the one they were cut from.
snipPass :: Table -> [Stmt] -> SnipM [Stmt]
snipPass table stmts
 = case stmts of
 	[]	-> return []
	(s:ss)
	 -> do 	(ssSnipped, s')	<- snipStmt table s
		ssRest		<- snipPass table ss
		return		$ ssSnipped ++ [s'] ++ ssRest


-- | Snip some bindings out of this stmt.
--	Returns the new stmt, and the bindings which were snipped.
snipStmt :: Table -> Stmt -> SnipM ([Stmt], Stmt)
snipStmt table xx
 = case xx of
	SBind mV x
	 -> do 	(ss, x')	<- snipX1 table Map.empty x
		return	(ss, SBind mV x')


-- | Enter into an expression on the RHS of a stmt.
snipX1 :: Table -> Map Var Type -> Exp -> SnipM ([Stmt], Exp)
snipX1	table env xx
 = trace ("snipX1: " % xx)
 $ case xx of
	XTau t	x
	 -> do	(ss, x')	<- snipX1 table env x
	 	return	(ss, XTau t x')

	-- Can't lift exprs out of the scope of binders,
	--	there might be free variables in them that would become out of scope
	XLAM{}			-> leaveIt xx
	XLam{}			-> leaveIt xx
	XLocal{}		-> leaveIt xx

	-- These are fine.
	XDo{}			-> leaveIt xx
	XMatch{}		-> leaveIt xx
	XLit{}			-> leaveIt xx
	XVar{}			-> leaveIt xx
	XPrim{}			-> leaveIt xx

	-- Snip compound exprs from the arguments of applications.
	XApp (XVar v t1) t2
	 | isFunWithSeaVoidParam t1
	 -> leaveIt xx

	XApp x1 x2 		-> snipXLeft table (substituteT (flip Map.lookup env) xx)

	XAPP (XVar v t1) t2	-> leaveIt xx

	XAPP x t
	 -> do	(ss, x')	<- snipX table (substituteT (flip Map.lookup env) x)
	 	return		(ss, XAPP x' t)


isFunWithSeaVoidParam ft
 = case ft of
	TApp (TCon TyConFun) (TCon (TyConData tcd _ _))
	 -> varId tcd == VarIdPrim TVoidU

	TApp a@TApp{} _
	 -> isFunWithSeaVoidParam a

	_ -> False


-- | Snip some stuff from an expression.
snipX table xx
 = trace ("snipX " % xx)
 $ case xx of
	XLAM{}			-> snipIt table xx

	XAPP{}			-> snipXLeft table xx

	XTau t x
	 -> do	(ss, x')	<- snipX table x
	 	return	(ss, XTau t x')

	XLam{}			-> snipIt table xx
	XApp{}			-> snipXLeft table xx

	XDo{}			-> snipIt table xx
	XMatch{}		-> snipIt table xx

	XLit{}			-> leaveIt xx

	-- snip XVars if they're defined at top level
	XVar v t
	 |   varIsBoundAtTopLevelInGlob (tableModuleGlob table) v
	  || varIsBoundAtTopLevelInGlob (tableHeaderGlob table) v
	 -> snipIt table xx

	 | otherwise
	 -> leaveIt xx

	XPrim{}			-> leaveIt xx

	-- we should never see XLocals as arguments..
	XLocal{}		-> leaveIt xx



-- | Snip some expressions from the left hand side of a function application.
--	On the left hand side we leave vars alone, and decend into other applications.
snipXLeft :: Table -> Exp -> SnipM ([Stmt], Exp)
snipXLeft table xx
 = case xx of
	XAPP x1@(XVar v t1) t2	-> leaveIt xx

	XAPP x t
	 -> do	(ss, x')	<- snipX table x
	 	return	(ss, XAPP x' t)

	XApp x1@(XVar v t1) x2
	 -> do	(ss2, x2')	<- snipXRight  table x2
	 	return	(ss2, XApp x1 x2')

	XApp x1 x2
	 -> do	(ss1, x1')	<- snipX    table x1
	 	(ss2, x2')	<- snipXRight table x2
		return	( ss1 ++ ss2
			, XApp x1' x2')

	_			-> snipX table xx


-- | Snip some expressions from the right hand side of a function application.
--	Right hand sides are arguments, snip function applications and anything else that looks good.
snipXRight :: Table -> Exp -> SnipM ([Stmt], Exp)
snipXRight table xx
 = case xx of
 	XApp{}
	 -> snipIt table xx

	-- leave literal values
	XAPP XLit{} (TVar kR _)
	 | kR 	== kRegion
	 -> leaveIt xx

	XAPP x t
	 -> case takeVar x of
	 	Nothing		-> snipIt table xx
		Just v
		   |   varIsBoundAtTopLevelInGlob (tableModuleGlob table) v
		    || varIsBoundAtTopLevelInGlob (tableHeaderGlob table) v
		   -> snipIt  table xx

		 | otherwise
		 -> leaveIt xx

	_ -> snipX table xx


-- | Snip some thing, creating a new statement.
--	If tablePreserve is turned on then preserve the type of the new var,
--	else just add a TNil. In this case we'll need to call Core.Reconstruct
--	to fill in the type annots later on.
snipIt :: Table -> Exp -> SnipM ([Stmt], Exp)
snipIt table xx
	| tablePreserveTypes table
	= do	b	<- newVarN NameValue
		let tX	= checkedTypeOfOpenExp (stage ++ ".snipIt") xx
	 	return	( [SBind (Just b) xx]
			, XVar b tX )

	| otherwise
	= do	b	<- newVarN NameValue
	 	return	( [SBind (Just b) xx]
			, XVar b TNil )


-- | Leave some thing alone.
leaveIt :: Exp -> SnipM ([Stmt], Exp)
leaveIt xx	= return ([], xx)


-- | Take the variable from an expression
--	(possibly wrapped in a type application)
takeVar :: Exp -> Maybe Var
takeVar	(XAPP x t)	= takeVar x
takeVar (XVar v t)	= Just v
takeVar _		= Nothing



