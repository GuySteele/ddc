
-- | Names used by the Sea core language profile.
--   Some of the primop types are also used by the SeaOutput profile.
module DDC.Core.Sea.Base.Name
        ( PrimTyCon     (..)
        , readPrimTyCon

        , PrimOp        (..)
        , readPrimOp

        , readLitInt
        , readLitPrimWordOfBits
        , readLitPrimIntOfBits)
where
import DDC.Base.Pretty
import Data.Char
import Data.List


-- PrimTyCon -----------------------------------------------------------------
-- | Primitive type constructors.
data PrimTyCon
        -- | The Void type.
        = PrimTyConVoid

        -- | Type of store pointers
        | PrimTyConPtr

        -- | Type of machine addresses.
        | PrimTyConAddr

        -- | Type of natural numbers,
        --   Used for field indices and general counters.
        | PrimTyConNat

        -- | Type of data type tags.
        | PrimTyConTag

        -- | Type of booleans.
        | PrimTyConBool

        -- | String of UTF8 characters.
        | PrimTyConString 

        -- | Unsigned words of the given length.
        | PrimTyConWord   Int

        -- | Signed integers of the given length.
        | PrimTyConInt    Int

        -- | Floating point numbers of the given length.
        | PrimTyConFloat  Int

        deriving (Eq, Ord, Show)


instance Pretty PrimTyCon where
 ppr tc
  = case tc of
        PrimTyConVoid           -> text "Void#"
        PrimTyConPtr            -> text "Ptr#"
        PrimTyConAddr           -> text "Addr#"
        PrimTyConNat            -> text "Nat#"
        PrimTyConTag            -> text "Tag#"
        PrimTyConBool           -> text "Bool#"
        PrimTyConString         -> text "String#"
        PrimTyConWord   bits    -> text "Word"  <> int bits <> text "#"
        PrimTyConInt    bits    -> text "Int"   <> int bits <> text "#"
        PrimTyConFloat  bits    -> text "Float" <> int bits <> text "#"


readPrimTyCon :: String -> Maybe PrimTyCon
readPrimTyCon str
        | str == "Void#"   = Just $ PrimTyConVoid
        | str == "Ptr#"    = Just $ PrimTyConPtr
        | str == "Addr#"   = Just $ PrimTyConAddr
        | str == "Nat#"    = Just $ PrimTyConNat
        | str == "Tag#"    = Just $ PrimTyConTag
        | str == "Bool#"   = Just $ PrimTyConBool
        | str == "String#" = Just $ PrimTyConString

        -- WordN#
        | Just rest     <- stripPrefix "Word" str
        , (ds, "#")     <- span isDigit rest
        , n             <- read ds
        , elem n [8, 16, 32, 64]
        = Just $ PrimTyConWord n

        -- IntN#
        | Just rest     <- stripPrefix "Int" str
        , (ds, "#")     <- span isDigit rest
        , n             <- read ds
        , elem n [8, 16, 32, 64]
        = Just $ PrimTyConInt n

        -- FloatN#
        | Just rest     <- stripPrefix "Float" str
        , (ds, "#")     <- span isDigit rest
        , n             <- read ds
        , elem n [32, 64]
        = Just $ PrimTyConInt n

        | otherwise
        = Nothing


-- PrimOp ---------------------------------------------------------------------
-- | Primitive numeric, comparison or logic operators.
--   We expect the backend/machine to be able to implement these directly.
data PrimOp
        -- arithmetic
        = PrimOpNeg
        | PrimOpAdd
        | PrimOpSub
        | PrimOpMul
        | PrimOpDiv
        | PrimOpRem

        -- comparison
        | PrimOpEq
        | PrimOpNeq
        | PrimOpGt
        | PrimOpGe
        | PrimOpLt
        | PrimOpLe

        -- boolean
        | PrimOpAnd
        | PrimOpOr

        -- bitwise
        | PrimOpShl
        | PrimOpShr
        | PrimOpBAnd
        | PrimOpBOr
        | PrimOpBXOr
        deriving (Eq, Ord, Show)


instance Pretty PrimOp where
 ppr op
  = let Just (_, n) = find (\(p, _) -> op == p) primOpNames
    in  (text n)


readPrimOp :: String -> Maybe PrimOp
readPrimOp str
  =  case find (\(_, n) -> str == n) primOpNames of
        Just (p, _)     -> Just p
        _               -> Nothing


-- | Names of primitve operators.
primOpNames :: [(PrimOp, String)]
primOpNames
 =      [ (PrimOpNeg,           "neg#")
        , (PrimOpAdd,           "add#")
        , (PrimOpSub,           "sub#")
        , (PrimOpMul,           "mul#")
        , (PrimOpDiv,           "div#")
        , (PrimOpRem,           "rem#")
        , (PrimOpEq ,           "eq#" )
        , (PrimOpNeq,           "neq#")
        , (PrimOpGt ,           "gt#" )
        , (PrimOpLt ,           "lt#" )
        , (PrimOpLe ,           "le#" )
        , (PrimOpAnd,           "and#")
        , (PrimOpOr ,           "or#" ) 
        , (PrimOpShl,           "shl#")
        , (PrimOpShr,           "shr#")
        , (PrimOpBAnd,          "band#")
        , (PrimOpBOr,           "bor#")
        , (PrimOpBXOr,          "bxor#") ]


-- Literals -------------------------------------------------------------------
-- Read a signed integer.
-- TODO: handle negative literals.
readLitInt :: String -> Maybe Integer
readLitInt str
        | (ds, "")      <- span isDigit str
        = Just $ read ds

        | otherwise
        = Nothing
        

-- Read a word like 1234w32
-- TODO: handle binary literals.
readLitPrimWordOfBits :: String -> Maybe (Integer, Int)
readLitPrimWordOfBits str1
        | (ds, str2)    <- span isDigit str1
        , Just str3     <- stripPrefix "w" str2
        , (bs, "#")     <- span isDigit str3
        = Just $ (read ds, read bs)

        | otherwise
        = Nothing


-- Read an integer like 1234i32.
-- TODO hande negative literals.
readLitPrimIntOfBits :: String -> Maybe (Integer, Int)
readLitPrimIntOfBits str1
        | (ds, str2)    <- span isDigit str1
        , Just str3     <- stripPrefix "i" str2
        , (bs, "#")     <- span isDigit str3
        = Just $ (read ds, read bs)

        | otherwise
        = Nothing
