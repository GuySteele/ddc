{-# OPTIONS -fwarn-incomplete-patterns #-}

module Core.Plate.Trans
	( TransTable(..)
	, TransM
	, transTableId
	, dropStateM

	, transZM
	, transZ

	, transformV

	, transformTM
	, transformT

	, transformSM
	, transformS

	, transformSS
	, transformSSM

	, transformX
	, transformXM

	, transformA

	, transformW)
where
import DDC.Main.Error
import DDC.Core.Exp
import DDC.Type
import DDC.Type.Data
import DDC.Var
import Util
import qualified Data.Map	as Map

stage = "Core.Plate.Trans"

-----
dropStateM ::	State s b -> b
dropStateM	m
 = let
 	(x', _)	= runState m (error "dropStateM: argh")
   in	x'

-----
class Monad m => TransM m a
 where	transZM :: TransTable m -> a -> m a

-----
transZ
	:: TransM (State ()) a
	=> TransTable (State ())
	-> a -> a

transZ	table x
	= evalState (transZM table x) ()

-----
instance Monad m => TransM m Var
 where	transZM = followV


-----
instance (Monad m, TransM m a)
	=> TransM m [a]
 where
  transZM table xx
   = 	mapM (transZM table) xx


-----
instance (Ord a, Monad m, TransM m a, TransM m b)
	=> TransM m (Map a b) where
  transZM table xx
   = liftM Map.fromList $ mapM (transZM table) $ Map.toList xx

-----
instance (Monad m, TransM m a)
	=> TransM m (Maybe a)
 where
  transZM table Nothing
   = 	return Nothing

  transZM table (Just x)
   = do	x'	<- transZM table x
   	return	$ Just x'


-----
instance (Monad m, TransM m a, TransM m b)
	=> TransM m (a, b)

 where	transZM table (x, y)
   	 = do	x'	<- transZM table x
	 	y'	<- transZM table y
		return	(x', y')



-----
transformV f s		= transZ	transTableId { transV	= \v -> return $ f v }				s
transformSM f s		= transZM 	transTableId { transS	= f,			decendT	= False } 	s
transformS f s		= transZ	transTableId { transS	= \s -> return $ f s, 	decendT	= False }	s
transformSS f ss 	= transZ  	transTableId { transSS	= \ss -> return $ f ss, decendT	= False }	ss
transformSSM f ss	= transZM	transTableId { transSS	= f, 			decendT	= False }	ss

-----
transformXM f x
 = transZM
 	transTableId
		{ transX	= f
		, decendT	= False }
	x


transformX f x
 = transZ
 	transTableId
		{ transX	= \x -> return $ f x
		, decendT	= False }
	x

-----
transformA f x
 = transZ
 	transTableId
		{ transA	= \x -> return $ f x
		, decendT	= False }
	x

-----
transformW f x
 = transZ
 	transTableId
		{ transW	= \x -> return $ f x
		, decendT	= False }
	x

-----
transformTM f t
 = transZM
 	transTableId
		{ transT	= f }
	t

transformT f t
 = transZ
 	transTableId
		{ transT	= \x -> return $ f x }
	t

-----
data TransTable m
	= TransTable
	{ transP	:: Top		-> m Top
	, transX	:: Exp		-> m Exp
	, transM	:: Prim		-> m Prim
	, transS	:: Stmt		-> m Stmt
	, transA	:: Alt		-> m Alt
	, transG	:: Guard	-> m Guard
	, transW	:: Pat		-> m Pat

	, transT	:: Type		-> m Type
	, transK	:: Kind		-> m Kind

	, transV	:: Var		-> m Var
	, transV_bind	:: Var		-> m Var
	, transV_free	:: Var		-> m Var

	, transSS	:: [Stmt]	-> m [Stmt]

	, transX_enter	:: Exp		-> m Exp

	, decendX	:: Bool
	, decendS	:: Bool
	, decendA	:: Bool
	, decendG	:: Bool

	, decendT	:: Bool
	, decendK	:: Bool }

-----
transTableId :: TransTable (State s)
transTableId
	= TransTable
	{ transP	= return
	, transX	= return
	, transM	= return
	, transS	= return
	, transA	= return
	, transG	= return
	, transW	= return

	, transT	= return
	, transK	= return

	, transV	= return
	, transV_bind	= return
	, transV_free	= return

	, transSS	= return
	, transX_enter	= return

	, decendX	= True
	, decendS	= True
	, decendA	= True
	, decendG	= True

	, decendT	= True
	, decendK	= True }

-----
followX  table x
 | decendX table	= transZM table x
 | otherwise		= return x

followSs table ss
 = do	ss2	<- mapM (followS table) ss
 	ss3	<- transSS table ss2
	return ss3

followS  table s
 | decendS table 	= transZM table s
 | otherwise		= return s

followAs table aa	= mapM (followA table) aa
followA  table a
 | decendA table	= transZM table a
 | otherwise		= return a

followGs table gg	= mapM (followG table) gg
followG table g
 | decendG table	= transZM table g
 | otherwise		= return g

followTs table tt	= mapM (followT table) tt
followT table t
 | decendT table	= transZM table t
 | otherwise		= return t

followK table k
 | decendK table	= transZM table k
 | otherwise		= return k

followV table v		= transV table v

followV_free table v
 = do	v1	<- transV_free table v
 	v2	<- transV      table v1
	return	v2

followV_bind table v
 = do	v1	<- transV_bind  table v
 	v2	<- transV	table v1
	return v2

followB_bind table BNil
 =	return BNil

followB_bind table (BVar v)
 = do	v1	<- transV_bind  table v
 	v2	<- transV	table v1
	return (BVar v2)

followB_bind table (BMore v t)
 = do	v1	<- transV_bind  table v
 	v2	<- transV	table v1
	t'	<- followT table t
	return (BMore v2 t')


-----
instance Monad m => TransM m Top where
 transZM table p
  = case p of
	PBind v x
	 -> do	v'		<- followV table v
		x'		<- followX table x
		transP table	$ PBind v' x'

	PExtern v tv to
	 -> do	v'		<- followV table v
	 	tv'		<- followT table tv
		to'		<- followT table to
		transP table	$ PExtern v' tv' to'

	PData ddef@(DataDef
		{ dataDefName	= v
		, dataDefParams	= vksParam
		, dataDefCtors	= ctors })

	 -> do	v'		<- transZM table v
		vksParam'	<- transZM table vksParam
		ctors'		<- transZM table ctors
	 	transP table 	$ PData ddef
				{ dataDefName	= v'
				, dataDefParams	= vksParam'
				, dataDefCtors	= ctors' }
	PRegion{}
	 ->	transP table p

	PEffect{}
	 -> 	transP table p

	PClass{}
	 ->	transP table p

	PClassDict{}
	 ->	transP table p

	PClassInst v ts defs
	 -> do	defs'		<- transZM table defs
	 	return		$ PClassInst v ts defs'


-----
instance Monad m => TransM m CtorDef where
 transZM table cc
  = case cc of
  	CtorDef v t arity tag fields
	 -> do	v'		<- followV table v
	 	t'		<- transZM table t
		return		$ CtorDef v' t' arity tag fields


-----
instance Monad m => TransM m Exp where
 transZM table xx
  = do	xx2	<- transX_enter table xx
 	transXM2 table xx2

transXM2 table xx
 = case xx of
	XNil
	 ->	transX table xx

	-- core constructs
	XVar v t
	 -> do	v'		<- followV_free  table v
		t'		<- followT table t
	 	transX table	$ XVar v' t'

	XPrim m t
	 -> do	m'		<- transZM table m
		t'		<- followT table t
		transX table	$ XPrim m' t'

	XLAM v k x
	 -> do	v'		<- followB_bind table v
	 	k'		<- followK table k
		x'		<- followX table x
		transX table	$ XLAM v' k' x'

	XLam v t x eff clo
	 -> do	v'		<- followV_bind table v
		t'		<- followT table t
		x'		<- followX table x
		eff'		<- followT table eff
		clo'		<- followT table clo
		transX table	$ XLam v' t' x' eff' clo'

	XAPP x c
	 -> do	x'		<- followX table x
	 	c'		<- followT table c
		transX table	$ XAPP x' c'

	XApp x1 x2
	 -> do	x1'		<- followX table x1
	 	x2'		<- followX table x2
		transX table	$ XApp x1' x2'

	XTau t x
	 -> do	t'		<- followT table t
	 	x'		<- followX table x
		transX table	$ XTau t' x'

	XDo ss
	 -> do	ss'		<- followSs table ss
	 	transX table	$ XDo ss'

	XMatch  aa
	 -> do	aa'		<- followAs table aa
		transX table	$ XMatch aa'

	XLit l
	 ->  do	transX table	$ XLit l

	XLocal v vts x
	 -> do	v'		<- followV_bind  table v
		let (vs, ts)	= unzip vts
		vs'		<- mapM (followV_free table) vs
		ts'		<- mapM (followT table) ts
		let vts'	= zip vs' ts'
	 	x'		<- followX  table x
		transX table	$ XLocal v' vts' x'




instance Monad m => TransM m Prim where
 transZM table tt
  = case tt of
	MForce			-> transM table tt
	MBox{} 			-> transM table tt
	MUnbox{}		-> transM table tt
	MOp{}			-> transM table tt
	MCast{}			-> transM table tt
	MCoerce{}		-> transM table tt
	MPtr{}			-> transM table tt
	MCall{}			-> transM table tt


instance Monad m => TransM m Type where
 transZM table tt
  = case tt of
 	TNil
	 ->	transT table tt

	TForall b k1 t2
	 -> do	b'		<- followB_bind table b
	 	k1'		<- followT table k1
	 	t2'		<- followT table t2
	 	transT table	$ TForall b' k1' t2'

	TConstrain t Constraints { crsEq, crsMore, crsOther }
	 -> do	t'		<- transZM table t
		crsEq'		<- liftM Map.fromList $ transZM table $ Map.toList crsEq
		crsMore'	<- liftM Map.fromList $ transZM table $ Map.toList crsMore
		crsOther'	<- transZM table crsOther
		return	$ TConstrain t' (Constraints crsEq' crsMore' crsOther')

	TSum k ts
	 -> do	ts'		<- followTs table ts
	 	transT table	$ TSum k ts'

	TVar k (UVar v)
	 -> do	v'		<- followV_free table v
	 	transT table	$ TVar k (UVar v')

	TVar k (UMore v t)
	 -> do	v'		<- followV_free table v
	 	t'		<- followT table t
		transT table	$ TVar k $ UMore v' t'

	TVar k UIndex{}
	 ->	transT table	$ tt

	TApp t1 t2
	 -> do	t1'		<- followT table t1
		t2'		<- followT table t2
		transT table	$ TApp t1' t2'

	TCon tyCon
	 -> do	tyCon'		<- transZM table tyCon
	 	transT table	$ TCon tyCon'

	_ 	-> panic stage
		$  "transZM[Type]: no match for " % show tt

-- TyCon -------------------------------------------------------------------------------------------
instance Monad m => TransM m TyCon where
 transZM table tt
  = case tt of
  	TyConFun{}		-> return tt

	TyConData { tyConName }
	 -> do	name'	<- followV_free table tyConName
	 	return	$ tt { tyConName = name' }

	TyConEffect { tyConEffect = TyConEffectTop v }
	 -> do	v'	<- followV_free table v
		return	$ tt { tyConEffect = TyConEffectTop v }

	TyConEffect{}		-> return tt

	-- BUGS: do we really want to ignore the tag var?
	TyConClosure{}		-> return tt

	TyConWitness { tyConWitness = TyConWitnessMkVar v }
	 -> do	v'	<- followV_free table v
	 	return	$ tt { tyConWitness = TyConWitnessMkVar v }

	TyConWitness{}		-> return tt
	TyConElaborate{}	-> return tt


-- Fetter ------------------------------------------------------------------------------------------
instance Monad m => TransM m Fetter where
 transZM table ff
  = case ff of
  	FWhere (TVar k (UVar v)) t
	 -> do	v'	<- followV_bind table v
	 	t'	<- followT table t
		return	$ FWhere (TVar k $ UVar v') t'

	FMore (TVar k (UVar v)) t
	 -> do	v'	<- followV_bind table v
	 	t'	<- followT table t
		return	$ FMore (TVar k $ UVar v') t'

	_	-> panic stage
		$ "transZM[Fetter]: no match for " % show ff


-- Kind --------------------------------------------------------------------------------------------
instance Monad m => TransM m Kind where
 transZM table kk
  = case kk of
	KNil		-> return KNil

	KCon{}		-> return kk

	KFun k1 k2
	 -> do	k1'	<- followK table k1
	 	k2'	<- followK table k2
		return	$ KFun k1' k2'

	KApp k1 t2
	 -> do	k1'	<- followK table k1
		t2'	<- followT table t2
		return	$ KApp k1' t2'

	KSum ks
	 -> do	ks'	<- mapM (followK table) ks
	 	return	$ KSum ks'

-----
instance Monad m => TransM m Stmt where
 transZM table s
  = case s of
	SBind mV x
	 -> do	mV'		<- liftToMaybe (followV_bind table) mV
		x'		<- followX table x
		transS table	$ SBind mV' x'


-----
instance Monad m => TransM m Alt where
 transZM table a
  = case a of
 	AAlt gs x
	 -> do	gs'		<- followGs table gs
	 	x'		<- followX  table x
		transA table	$ AAlt gs' x'


-----
instance Monad m => TransM m Guard where
 transZM table g
  = case g of
	GExp w x
	 -> do	w'		<- transZM table w
	 	x'		<- followX table x
		transG table	$ GExp w' x'


-----
instance Monad m => TransM m Pat where
 transZM table xx
  = case xx of
	WVar v
	 -> do	v'		<- followV_bind table v
	 	transW table	$ WVar v'

	WLit spos c
	 ->  	transW table	$ WLit spos c

	WCon spos v lvt
	 -> do	v'		<- followV_free table v

		let (ls, vs, ts)	= unzip3 lvt
		vs'		<- mapM (followV_bind table) vs
		ts'		<- followTs table ts
		let lvt'	= zip3 ls vs' ts'

	 	transW table	$ WCon spos v' lvt'

