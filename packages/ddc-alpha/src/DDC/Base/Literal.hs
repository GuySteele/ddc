{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | Representation of literal values.
module DDC.Base.Literal
	( Literal    (..)
	, LiteralFmt (..)
	, defaultLiteralFmt)
where
import DDC.Main.Pretty
import DDC.Main.Error
import DDC.Base.DataFormat

stage	= "DDC.Base.Literal"

-- | A literal value.
--	This stores literal values as we see them in the source program.
--	We need enough numeric precison here to represent any possible
--	value we might get in the source.
data Literal
	= LBool		Bool		-- ^ Boolean.
	| LWord		Integer		-- ^ An unsigned integer.
	| LInt		Integer		-- ^ An integer.
	| LFloat	Double		-- ^ A floating point number.
	| LChar		Char		-- ^ A character.
	| LString	String		-- ^ A string.
	deriving (Show, Eq)


-- | A Literal value along with a format specifier saying 
--	whether it's boxed or not, and how wide we should
--	take it to be.
data LiteralFmt
	= LiteralFmt	Literal DataFormat
	deriving (Show, Eq)
	
	
instance Pretty LiteralFmt PMode where
 ppr (LiteralFmt lit fmt)
  = case (fmt, lit) of
	(Unboxed,	LBool True)	-> ppr "true#"
	(Unboxed, 	LBool False)	-> ppr "false#"
	
	(Boxed,   	LWord w)	-> w % "u"
	(BoxedBits b,	LWord w)	-> w % "u"  % b
	(Unboxed,  	LWord w)	-> w % "#u"
	(UnboxedBits b,	LWord w)	-> w % "#u" % b

	(Boxed,   	LInt i)		-> ppr i
	(BoxedBits b,	LInt i)		-> i % "i"  % b
	(Unboxed,  	LInt i)		-> i % "#i"
	(UnboxedBits b,	LInt i)		-> i % "#i" % b

	(Boxed,   	LFloat f)	-> ppr f
	(BoxedBits b,	LFloat f)	-> f % "f"  % show b
	(Unboxed,  	LFloat f)	-> f % "#f"
	(UnboxedBits b,	LFloat f)	-> f % "#f" % show b
	
	(BoxedBits 32,	 LChar c) 	-> ppr $ show c
	(UnboxedBits 32, LChar c) 	-> ppr $ show c % "#"

	(Boxed, 	LString s)      -> ppr $ show s
	(Unboxed,	LString s)      -> show s % "#"
	
	-- Literals don't exist in all the possible `DataFormat`s.
	-- For example, there is no String32# or Char32# format.
	_  	-> panic stage
		$  "showFormatLiteral: bad combination of format and literal value\n"
		%  "    format  = " % show fmt % "\n"
		%  "    literal = " % show lit % "\n" 


instance Pretty Literal PMode where
 ppr lit 
  = case lit of
	LBool	b
	 -> case b of
	 	True	-> ppr "true"
		False	-> ppr "false"
		
	LWord i		-> ppr $ show i 		
  	LInt    i	-> ppr $ show i
	LFloat  f	-> ppr $ show f
	LChar   c	-> ppr $ show c
	LString s	-> ppr $ show s



-- | Default literals to the machine type.
--   TODO: From the source language, the plain Word Int Float types should be abstract,
--         because the widths can change on a machine-to-machine basis.
--
--         In the compiler however, we should default them to an appropriate width
--         depending on what platform we're on.
--         
defaultLiteralFmt :: LiteralFmt -> LiteralFmt
defaultLiteralFmt litFmt@(LiteralFmt lit fmt)
 = case (lit, fmt) of
	(LWord _,  Boxed)	-> LiteralFmt lit (BoxedBits   32)
	(LWord _,  Unboxed)	-> LiteralFmt lit (UnboxedBits 32)

	(LInt _,   Boxed)	-> LiteralFmt lit (BoxedBits   32)
	(LInt _,   Unboxed)	-> LiteralFmt lit (UnboxedBits 32)

	(LFloat _, Boxed)	-> LiteralFmt lit (BoxedBits   32)
	(LFloat _, Unboxed)	-> LiteralFmt lit (UnboxedBits 32)
	_			-> litFmt
	