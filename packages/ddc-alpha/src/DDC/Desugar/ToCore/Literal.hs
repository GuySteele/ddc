{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
-- | Conversion of literal values.
module DDC.Desugar.ToCore.Literal
	(toCoreXLit)
where
import DDC.Desugar.ToCore.Base
import DDC.Main.Error
import DDC.Base.Literal
import DDC.Base.DataFormat
import Shared.VarPrim
import qualified DDC.Type			as T
import qualified DDC.Desugar.Exp		as D
import qualified DDC.Core.Exp			as C

stage		= "DDC.Desugar.ToCore.Literal"

-- | Convert a literal to core
--	The desugared language supports boxed literals, but all literals in the core
--	should be unboxed.
toCoreXLit :: T.Type -> D.Exp Annot -> C.Exp
toCoreXLit tt xLit
 	= toCoreXLit' (T.stripToBodyT tt) xLit

toCoreXLit' tt (D.XLit _ litfmt@(LiteralFmt lit fmt))

	-- raw unboxed strings need their region applied
	| LString _	<- lit
	, Unboxed	<- fmt
	= let	Just (_, _, [tStr]) 	= T.takeTData tt
		Just (_, _, [tR])	= T.takeTData tStr
	  in	C.XAPP (C.XLit litfmt) tR

	-- other unboxed literals have kind *, so there is nothing more to do
	| dataFormatIsUnboxed fmt
	= C.XLit litfmt
	
	-- unboxed strings have kind % -> *, 
	--	so we need to apply the region to the unboxed literal
	--	when building the boxed version.
	| LString _	<- lit
	, Boxed		<- fmt
	= let	Just (_, _, [tR]) = T.takeTData tt

		Just fmtUnboxed	  = dataFormatUnboxedOfBoxed fmt
		tBoxed		  = tt
		Just tUnboxed	  = T.takeUnboxedOfBoxedType tBoxed
		tFun		  = T.makeTFun 	(T.tPtrU `T.TApp` tUnboxed)
						tBoxed
						(T.TApp T.tRead tR)
						T.tEmpty

	  in	C.XApp	(C.XVar  primBoxString tFun) 
			(C.XAPP  (C.XLit $ LiteralFmt lit fmtUnboxed) tR)

	-- the other unboxed literals have kind *, 
	--	so we can just pass them to the the boxing primitive directly.
	| otherwise
	= let	Just fmtUnboxed	= dataFormatUnboxedOfBoxed fmt
		tBoxed		= tt
		Just tUnboxed	= T.takeUnboxedOfBoxedType tBoxed
		Just ptUnboxed	= T.takePrimTypeOfType tUnboxed
		tFun		= T.makeTFun tUnboxed tBoxed T.tPure T.tEmpty
		
	  in	C.XApp	(C.XPrim (C.MBox ptUnboxed) tFun)
			(C.XLit $ LiteralFmt lit fmtUnboxed)
	

toCoreXLit' _ _
	= panic stage
	$ "toCoreXLit: not an XLit"
