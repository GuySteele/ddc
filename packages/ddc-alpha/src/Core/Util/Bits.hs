
-- | Bits and pieces for working on Core.Exp.
--	These are the simplest utils at the bottom of the dependency tree.
--	They shouldn't depend on any other Core modules besides Exp.
--
module Core.Util.Bits
	( isXApp
	, isXAPP
	, isXLambda
	, isXLAMBDA
	, isXTau
	, isXMatch
	, isXDo
	, isXLocal
	, isXVar
	
	, isCafP 
	, isFunctionX
	, stripXTau
	, hasEmbeddedLambdasX
	, hasLambdasX
	
	-- projections	
	, takeVarOfStmt
	, takeVarOfPBind
	
	-- application
	, buildApp
	, flattenAPPs
	, flattenApps
	, unflattenApps
	, splitApps

	-- lambda		
	, chopLambdas
	, addLAMBDAs)
where
import DDC.Core.Exp
import DDC.Type
import DDC.Var
import Util

-- Predicates --------------------------------------------------------------------------------------
isXApp x
	= or
	[ x =@= XAPP{}
	, x =@= XApp{} ]

isXAPP	  XAPP{}	= True
isXAPP	  _		= False
	
isXLambda XLam{}	= True
isXLambda _		= False

isXLAMBDA XLAM{}	= True
isXLAMBDA _		= False

isXTau	  XTau{}	= True
isXTau	  _		= False

isXMatch  XMatch{}	= True
isXMatch  _		= False

isXDo     XDo{}		= True
isXDo     _		= False

isXLocal  XLocal{}	= True
isXLocal  _		= False

isXVar	  XVar{}	= True
isXVar	  _		= False

-- FFS XTaus were never a good idea.
stripXTau xx
 = case xx of
	XTau _ x	-> stripXTau x
	_		-> xx

-- | Check whether a top level thing is a CAF binding
isCafP :: Top -> Bool
isCafP	pp
 = case pp of
 	PBind v x	-> isCafX x

	PExtern v _ to
	 |  Just 0	<- takeValueArityOfType to
	 -> True
	
	_		-> False
	
isCafX xx
 = case xx of
 	XLAM v k x	-> isCafX x
	XLam{}		-> False
	XTau t x	-> isCafX x
	XLocal v vs x	-> isCafX x
	_		-> True


-- | Test whether an expression is syntactically a (value) function.
--   It might be wrapped by type lambdas, type applications, or annotations 
isFunctionX :: Exp	-> Bool
isFunctionX xx
 = case xx of
	XLAM	v t x	-> isFunctionX x
	XAPP	x t	-> isFunctionX x
	XTau	t x	-> isFunctionX x
	XLam{}		-> True
	_		-> False


--  | Test whether an expression contains any _embedded_ lambda abstractions,
--    not including the outermost ones.
--
--	eg \x -> \y -> f x 3		-- no embedded lambdas
--	eg \x -> \y -> f (\z -> z) 3	-- embeded lambda in first arg
--
hasEmbeddedLambdasX ::	Exp -> Bool
hasEmbeddedLambdasX xx
 = case xx of
 	XLAM	v t x		-> hasEmbeddedLambdasX x
	XAPP 	x t		-> hasEmbeddedLambdasX x
	XTau	t x		-> hasEmbeddedLambdasX x
	XLocal	v vs x		-> hasEmbeddedLambdasX x
	XLam	v t x eff clo	-> hasEmbeddedLambdasX x	
	_			-> hasLambdasX xx


-- | Checks whether an expression contains any (value) lambda abstractions.
hasLambdasX ::	Exp 	-> Bool
hasLambdasX	x
 = case x of
	XLAM	v t x		-> hasLambdasX x
	XAPP x t		-> hasLambdasX x
	XTau	t x		-> hasLambdasX x

	XLam{}			-> True
	XApp x1 x2		-> hasLambdasX x1 || hasLambdasX x2
	XDo ss			-> or $ map hasLambdasS ss
	XMatch aa		-> or $ map hasLambdasA aa
	
	XLocal v vs x		-> hasLambdasX x

	_			-> False

 where	hasLambdasS	s
 	 = case s of
		SBind v x	-> hasLambdasX x
	
	hasLambdasA	a
 	 = case a of
 		AAlt 	gs x	-> hasLambdasX x


-- Projections -------------------------------------------------------------------------------------
takeVarOfPBind :: Top -> Maybe Var
takeVarOfPBind pp
 = case pp of
	PBind v _	-> Just v
	_		-> Nothing
	

takeVarOfStmt :: Stmt -> Maybe Var
takeVarOfStmt ss
 = case ss of
 	SBind mv x	-> mv


-- Application -------------------------------------------------------------------------------------
-- | Flatten outermost type applications in an expression.
flattenAPPs :: Exp -> [Either Exp Type]
flattenAPPs xx
	| XAPP x t	<- xx
	= flattenAPPs x ++ [Right t]

	| otherwise
	= [Left xx]

-- | Create an application from a list of expressions
--	buildApp [x1, x2, x3] => (x1 x2) x3
buildApp :: [Either Exp Type] -> Maybe Exp
buildApp xx
	= buildApp'
	$ reverse xx

buildApp' xx
	| Left x : []		<- xx
	= Just x
	
	| Right t : xs		<- xx
	, Just leftX		<- buildApp' xs
	= Just $ XAPP leftX t
	
	| Left x : xs	<- xx
	, Just leftX		<- buildApp' xs
	= Just $ XApp leftX x

	| otherwise
	= Nothing

-- | Flatten type and value applications of an expression.
flattenApps ::	Exp -> [Either Exp Type]
flattenApps x
	| XApp e1 e2	<- x
	= flattenApps e1 ++ [Left e2]

	| XAPP  x t		<- x
	= flattenApps x  ++ [Right t]

	| otherwise
	= [Left x]
	
	
-- | Build some type/value applications
unflattenApps :: [Either Exp Type] -> Exp
unflattenApps	xx
	
	| x1:x2:xs	<- xx
	, Left e1	<- x1
	, Left e2	<- x2
	= unflattenApps
	$ [Left $ XApp e1 e2] ++ xs
	
	| x1:x2:xs	<- xx
	, Left  e1	<- x1
	, Right e2	<- x2
	= unflattenApps
	$ [Left $ XAPP e1 e2] ++ xs
	
	| x1:[]		<- xx
	, Left e1	<- x1
	= e1


-- | Split out args and effects produced at each application
splitApps :: Exp -> [Either Exp Type]
splitApps xx
 = case xx of
 	XAPP e1 e2
	 -> splitApps e1 ++ [Right e2]
	
	XApp e1 e2 
	 -> splitApps e1 ++ [Left e2]
		
	_ -> [Left xx]
	
	
-- Lambda ------------------------------------------------------------------------------------------
-- | Chop the outer set of lambdas off a lambda expression and return the var-scheme pairs.
chopLambdas ::	Exp -> (Exp, [(Var, Type)])
chopLambdas	x

	| XLam v t e eff clo	<- x
	= let	(e', rest)	= chopLambdas e
	  in 	(e', (v, t) : rest)
	  
	| otherwise
	= (x, [])
	
-- | Add some type lambdas to an expression.	
addLAMBDAs ::	[(Bind, Kind)] -> Exp -> Exp
addLAMBDAs	vks x
 = case vks of
 	[]			-> x
	((v, k) : vks)		-> XLAM v k (addLAMBDAs vks x)

