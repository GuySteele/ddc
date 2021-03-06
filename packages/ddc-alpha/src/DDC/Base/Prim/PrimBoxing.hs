{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
-- | Primitive boxing functions.
module DDC.Base.Prim.PrimBoxing
	( readPrimBoxing
	, readPrimUnboxing)
where
import DDC.Base.Prim.PrimType


-- | Read the name of a primitive boxing function.
--   TODO: Make this more general.
readPrimBoxing :: String -> Maybe PrimType
readPrimBoxing str
 = case str of
	"boxWord8"	-> Just $ PrimTypeWord  $ Width 8
	"boxWord16"	-> Just $ PrimTypeWord  $ Width 16
	"boxWord32"	-> Just $ PrimTypeWord  $ Width 32
	"boxWord64"	-> Just $ PrimTypeWord  $ Width 64

	"boxInt8"	-> Just $ PrimTypeInt   $ Width 8
	"boxInt16"	-> Just $ PrimTypeInt   $ Width 16
	"boxInt32"	-> Just $ PrimTypeInt   $ Width 32
	"boxInt64"	-> Just $ PrimTypeInt   $ Width 64

	"boxFloat32"	-> Just $ PrimTypeFloat $ Width 32
	"boxFloat64"	-> Just $ PrimTypeFloat $ Width 64

	_		-> Nothing
	

-- | Read the name of a primitive unboxing function.
--   TODO: Make this more general.
readPrimUnboxing :: String -> Maybe PrimType
readPrimUnboxing str
 = case str of
	"unboxWord8"	-> Just $ PrimTypeWord  $ Width 8
	"unboxWord16"	-> Just $ PrimTypeWord  $ Width 16
	"unboxWord32"	-> Just $ PrimTypeWord  $ Width 32
	"unboxWord64"	-> Just $ PrimTypeWord  $ Width 64

 	"unboxInt8"	-> Just $ PrimTypeInt   $ Width 8
	"unboxInt16"	-> Just $ PrimTypeInt   $ Width 16
 	"unboxInt32"	-> Just $ PrimTypeInt   $ Width 32
	"unboxInt64"	-> Just $ PrimTypeInt   $ Width 64

	"unboxFloat32"	-> Just $ PrimTypeFloat $ Width 32
	"unboxFloat64"	-> Just $ PrimTypeFloat $ Width 64

	_		-> Nothing
	
	
