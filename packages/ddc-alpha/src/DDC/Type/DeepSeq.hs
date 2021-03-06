{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
-- | DeepSeq on Type expressions.
module DDC.Type.DeepSeq where

import DDC.Type.Exp
import DDC.Var
import Control.DeepSeq

instance DeepSeq Var
instance DeepSeq ClassId

instance DeepSeq Super where
 deepSeq xx y
  = case xx of
	SProp				-> y
	SBox 				-> y
	SFun 		s1 s2		-> deepSeq s1 $! deepSeq s2 y
	
 
instance DeepSeq Kind where
 deepSeq xx y
  = case xx of
	KNil				-> y
	KCon 		c  s		-> deepSeq c  $! deepSeq s  y
	KFun		k1 k2		-> deepSeq k1 $! deepSeq k2 y
	KApp		k1 t2		-> deepSeq k1 $! deepSeq t2 y
	KSum		ks		-> deepSeq ks y
	

instance DeepSeq KiCon where
 deepSeq xx y
  = case xx of
	KiConVar 	v		-> deepSeq v y
	_				-> y

instance DeepSeq Bind where
 deepSeq xx y
  = case xx of
	BNil{}				-> y
	BVar 		v		-> deepSeq v y
	BMore 		v t		-> deepSeq v $! deepSeq t y


instance DeepSeq Type where
 deepSeq xx y
  = case xx of
	TNil				-> y
	TForall		b k t		-> deepSeq b  $! deepSeq k $! deepSeq t y
	TApp		t1 t2		-> deepSeq t1 $! deepSeq t2 y
	TSum		k ts		-> deepSeq k  $! deepSeq ts y
	TCon		c		-> deepSeq c y
	TVar		k v		-> deepSeq k  $! deepSeq v y
	TError		k _		-> deepSeq k y
	TConstrain	t crs		-> deepSeq t  $! deepSeq crs y


instance DeepSeq Bound where
 deepSeq uu y
  = case uu of
	UVar		v		-> deepSeq v y
	UMore		v t		-> deepSeq v $! deepSeq t y
	UIndex		i		-> deepSeq i y
	UClass		c		-> deepSeq c y


instance DeepSeq Constraints where
 deepSeq (Constraints eqs mores others) y
	= deepSeq eqs $! deepSeq mores $! deepSeq others y


instance DeepSeq TyCon where
 deepSeq xx y
  = case xx of
	TyConFun 			-> y
	TyConData 	n k _		-> deepSeq n $! deepSeq k y
	TyConWitness 	c k		-> deepSeq c $! deepSeq k y
	TyConEffect{}			-> y
	TyConClosure{}			-> y
	TyConElaborate{}		-> y

instance DeepSeq TyConWitness where
 deepSeq xx y
  = case xx of
	TyConWitnessMkVar v		-> deepSeq v y
	_				-> y


instance DeepSeq Fetter where
 deepSeq xx y
  = case xx of
	FConstraint 	v ts		-> deepSeq v  $! deepSeq ts y
	FWhere 		t1 t2		-> deepSeq t1 $! deepSeq t2 y
	FMore  		t1 t2		-> deepSeq t1 $! deepSeq t2 y
	FProj  		j v t1 t2	-> deepSeq j  $! deepSeq v $! deepSeq t1 $! deepSeq t2 y


instance DeepSeq TProj where
 deepSeq xx y
  = case xx of
	TJField 	v		-> deepSeq v y
	TJFieldR 	v		-> deepSeq v y
	TJIndex  	v		-> deepSeq v y
	TJIndexR 	v		-> deepSeq v y
	
