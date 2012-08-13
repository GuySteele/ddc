
module DDC.Core.Eval.Name 
        ( Name    (..)
        , PrimCon (..)
        , PrimOp  (..)
        , Loc     (..)
        , Rgn     (..)
        , Cap     (..)
        , readName
        , lexModuleString
        , lexExpString)
where
import DDC.Core.Lexer
import DDC.Base.Pretty
import DDC.Data.Token
import Data.Typeable
import Data.Char


-- | Names of things recognised by the evaluator.
-- 
data Name 
        -- Names whose types are bound in the environments.
        = NameVar     String     -- ^ User variables.
        | NameCon     String     -- ^ User constructors.

        -- Names whose types are baked in, and should be attached to 
        -- the `Bound` constructor that they appear in.
        | NameInt     Integer    -- ^ Integer literals (which data constructors).
        | NamePrimCon PrimCon    -- ^ Primitive constructors (eg @List, Nil@).
        | NamePrimOp  PrimOp     -- ^ Primitive operators    (eg @addInt, subInt@).

        | NameLoc     Loc        -- ^ Store locations.
        | NameRgn     Rgn        -- ^ Region handles.
        | NameCap     Cap        -- ^ Store capabilities.
        deriving (Show, Eq, Ord, Typeable)
        

instance Pretty Name where
 ppr nn
  = case nn of
        NameVar     v   -> text v
        NameCon     c   -> text c
        NameInt     i   -> text (show i)
        NamePrimCon c   -> ppr c
        NamePrimOp  op  -> ppr op
        NameLoc     l   -> ppr l
        NameRgn     r   -> ppr r
        NameCap     p   -> ppr p


-- Locations ------------------------------------------------------------------
-- | A store location.
--
--  These are pretty printed like @L4#@.
data Loc
        = Loc Int
        deriving (Eq, Ord, Show)

instance Pretty Loc where
 ppr (Loc l)    
        = text "L" <> text (show l) <> text "#"
 

-- Regions --------------------------------------------------------------------
-- | A region handle.
--
--  These are pretty printed like @R5#@.
data Rgn
        = Rgn Int
        deriving (Eq, Ord, Show)

instance Pretty Rgn where
 ppr (Rgn r)    
        = text "R" <> text (show r) <> text "#"


-- Capabilities --------------------------------------------------------------
-- | These are primitive witnesses that guarantee the associated property
--   of the program. Ostensibly, they are only introduced by the system
--   at runtime, but for testing purposes we can also inject them into
--   the source program.
data Cap
        -- | Witness that a region is global.
        --   Global regions live for the duration of the program and are not
        --   deallocated in a stack like manner. This lets us hide the use of
        --   such regions, and rely on the garbage collector to reclaim the
        --   space.
        = CapGlobal   -- Global#   :: [r: %]. Global r

        -- | Witness that a region is constant.
        --   This lets us purify read and allocation effects on it,
        --   and prevents it from being Mutable.
        | CapConst    -- Const#    :: [r: %]. Const r
        
        -- | Witness that a region is mutable.
        --   This lets us update objects in the region, 
        --   and prevents it from being Constant.
        | CapMutable  -- Mutable#  :: [r: %]. Mutable r

        -- | Witness that some regions are distinct
        --   This lets us perform aliasing based optimisations.
        | CapDistinct -- Distinct# :: [r1 r2 : %]. Distinct r1 r2
             
        -- | Witness that a region is lazy.
        --   This lets is allocate thunks into the region,
        --   and prevents it from being Manifest.
        | CapLazy     -- Lazy#     :: [r: %].Lazy r
        
        -- | Witness that a region is manifest.
        --   This ensures there are no thunks in the region,
        --   which prevents it from being Lazy.
        | CapManifest -- Manifest# :: [r: %]. Manifest r
        deriving (Eq, Ord, Show)


instance Pretty Cap where
 ppr cp
  = case cp of
        CapGlobal       -> text "Global#"
        CapConst        -> text "Const#"
        CapMutable      -> text "Mutable#"
        CapDistinct     -> text "Distinct#"
        CapLazy         -> text "Lazy#"
        CapManifest     -> text "Manifest#"


-- PrimCons -------------------------------------------------------------------
-- | A primitive constructor.
data PrimCon
        -- Type constructors
        = PrimTyConInt          -- ^ @Int@  type constructor.
        | PrimTyConPair         -- ^ @Pair@ type constructor.
        | PrimTyConList         -- ^ @List@ type constructor.

        -- Implement lists as primitives until we have data decls working
        | PrimDaConPr           -- ^ @P@ data construct (pairs).
        | PrimDaConNil          -- ^ @Nil@ data constructor.
        | PrimDaConCons         -- ^ @Cons@ data constructor.
        deriving (Show, Eq, Ord)

instance Pretty PrimCon where
 ppr con
  = case con of
        PrimTyConInt    -> text "Int"
        PrimTyConPair   -> text "Pair"
        PrimTyConList   -> text "List"

        PrimDaConPr     -> text "Pr"
        PrimDaConNil    -> text "Nil"
        PrimDaConCons   -> text "Cons"


-- PrimOps --------------------------------------------------------------------
-- | A primitive operator.
data PrimOp
        = PrimOpNegInt
        | PrimOpAddInt
        | PrimOpSubInt
        | PrimOpMulInt
        | PrimOpDivInt
        | PrimOpEqInt
        | PrimOpUpdateInt
        | PrimOpCopyInt
        deriving (Show, Eq, Ord)


instance Pretty PrimOp where
 ppr op
  = case op of
        PrimOpNegInt    -> text "negInt"
        PrimOpAddInt    -> text "addInt"
        PrimOpSubInt    -> text "subInt"
        PrimOpMulInt    -> text "mulInt"
        PrimOpDivInt    -> text "divInt"
        PrimOpEqInt     -> text "eqInt"
        PrimOpUpdateInt -> text "updateInt"
        PrimOpCopyInt	-> text "copyInt"


-- Parsing --------------------------------------------------------------------
-- | Read a primitive name.
readName :: String -> Maybe Name
readName []     = Nothing
readName str@(c:rest)
        -- primops and variables.
        | isLower c    
        = case (c:rest) of
                "negInt"        -> Just $ NamePrimOp PrimOpNegInt
                "addInt"        -> Just $ NamePrimOp PrimOpAddInt
                "subInt"        -> Just $ NamePrimOp PrimOpSubInt
                "mulInt"        -> Just $ NamePrimOp PrimOpMulInt
                "divInt"        -> Just $ NamePrimOp PrimOpDivInt
                "eqInt"         -> Just $ NamePrimOp PrimOpEqInt
                "updateInt"     -> Just $ NamePrimOp PrimOpUpdateInt
                "copyInt"	-> Just $ NamePrimOp PrimOpCopyInt
                _               -> Just $ NameVar str

        -- integers
        | str == "Int"          = Just $ NamePrimCon PrimTyConInt

        | c == '-'
        , all isDigit rest
        = Just $ NameInt (read str)

        | all isDigit str
        = Just $ NameInt (read str)

        -- pairs
        | str == "Pair"         = Just $ NamePrimCon PrimTyConPair
        | str == "Pr"           = Just $ NamePrimCon PrimDaConPr
        
        -- lists 
        | str == "List"         = Just $ NamePrimCon PrimTyConList
        | str == "Nil"          = Just $ NamePrimCon PrimDaConNil
        | str == "Cons"         = Just $ NamePrimCon PrimDaConCons
        
        -- region handles
        | c == 'R'
        , (ds, "#")             <- span isDigit rest
        , not $ null ds
        = Just $ NameRgn (Rgn $ read ds)
        
        -- store locations
        | c == 'L'
        , (ds, "#")             <- span isDigit rest
        , not $ null ds
        = Just $ NameLoc (Loc $ read ds)
        
        -- store capabilities
        | str == "Global#"      = Just $ NameCap CapGlobal
        | str == "Const#"       = Just $ NameCap CapConst
        | str == "Mutable#"     = Just $ NameCap CapMutable
        | str == "Distinct#"    = Just $ NameCap CapDistinct
        | str == "Lazy#"        = Just $ NameCap CapLazy
        | str == "Manifest#"    = Just $ NameCap CapManifest

        -- other constructors
        | isUpper c
        = Just $ NameCon str
        
        | otherwise
        = Nothing


-- | Lex a string to tokens, using primitive names.
--
--   The first argument gives the starting source line number.
lexModuleString :: String -> Int -> String -> [Token (Tok Name)]
lexModuleString sourceName lineStart str
 = map rn $ lexModuleWithOffside sourceName lineStart str
 where rn (Token strTok sp) 
        = case renameTok readName strTok of
                Just t' -> Token t' sp
                Nothing -> Token (KJunk "lexical error") sp


-- | Lex a string to tokens, using primitive names.
--
--   The first argument gives the starting source line number.
lexExpString :: String -> Int -> String -> [Token (Tok Name)]
lexExpString sourceName lineStart str
 = map rn $ lexExp sourceName lineStart str
 where rn (Token strTok sp) 
        = case renameTok readName strTok of
                Just t' -> Token t' sp
                Nothing -> Token (KJunk "lexical error") sp

 
