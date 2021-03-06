{-# OPTIONS -fno-warn-type-defaults #-}


module Llvm.Runtime.Data where

import Llvm
import LlvmM
import Llvm.Runtime.Object
import Llvm.Runtime.Struct
import Llvm.Util


panicOutOfSlots :: LlvmFunctionDecl
panicOutOfSlots = LlvmFunctionDecl "_panicOutOfSlots" External CC_Ccc LMVoid FixedArgs [] ptrAlign

allocCollect :: LlvmFunctionDecl
allocCollect = LlvmFunctionDecl "_allocCollect" External CC_Ccc LMVoid FixedArgs [(i32, [])] ptrAlign


ddcSlotPtr :: LlvmVar
ddcSlotPtr = pVarLift (LMGlobalVar "_ddcSlotPtr" ppObj External Nothing ptrAlign False)

ddcSlotMax :: LlvmVar
ddcSlotMax = pVarLift (LMGlobalVar "_ddcSlotMax" ppObj External Nothing ptrAlign False)

ddcSlotBase :: LlvmVar
ddcSlotBase = pVarLift (LMGlobalVar "_ddcSlotBase" ppObj External Nothing ptrAlign False)


ddcHeapPtr :: LlvmVar
ddcHeapPtr = pVarLift (LMGlobalVar "_ddcHeapPtr" pChar External Nothing ptrAlign False)

ddcHeapMax :: LlvmVar
ddcHeapMax = pVarLift (LMGlobalVar "_ddcHeapMax" pChar External Nothing ptrAlign False)


localSlotBase :: LlvmVar
localSlotBase = LMNLocalVar "local.slotPtr" ppObj


force :: LlvmFunctionDecl
force = LlvmFunctionDecl "_force" External CC_Ccc pObj FixedArgs [(pObj, [])] ptrAlign


boxRef :: LlvmFunctionDecl
boxRef = LlvmFunctionDecl "_boxRef" External CC_Ccc pObj FixedArgs [(pObj, []), (pChar, [])] ptrAlign


forceObj :: LlvmVar -> LlvmM LlvmVar
forceObj orig
 = do	addGlobalFuncDecl force
	let fun	= LMGlobalVar "_force" (LMFunction force) External Nothing Nothing True
	forced	<- newUniqueNamedReg "forced" pObj
	addBlock [ Assignment forced (Call StdCall fun [orig] []) ]
	return forced


followObj :: LlvmVar -> LlvmM LlvmVar
followObj orig
 = do	addComment $ "followObj " ++ show orig
	let index = fst $ structFieldLookup ddcSuspIndir "obj"
	r0 	<- newUniqueReg pStructSuspIndir
	r1	<- newUniqueReg ppObj
	r2	<- newUniqueReg pObj
	addBlock
		[ Assignment r0 (Cast LM_Bitcast orig pStructSuspIndir)
		, Assignment r1 (GetElemPtr False r0 [i32LitVar 0, i32LitVar index])
		, Assignment r2 (Load r1) ]
	return	r2


getObjTag :: LlvmVar -> LlvmM LlvmVar
getObjTag obj
 = do	r0	<- newUniqueReg $ pLift i32
	r1	<- newUniqueReg i32
	val	<- newUniqueNamedReg "tag.val" i32
	addBlock
		[ Assignment r0 (GetElemPtr False obj [llvmWordLitVar 0, i32LitVar 0])
		, Assignment r1 (Load r0)
		, Assignment val (LlvmOp LM_MO_LShr r1 (i32LitVar 8))
		]
	return	val

