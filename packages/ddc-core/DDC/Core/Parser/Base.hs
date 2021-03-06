
module DDC.Core.Parser.Base
        ( Parser
        , pModuleName
        , pQualName
        , pName
        , pWbCon,       pWbConSP
        , pCon,         pConSP
        , pLit,         pLitSP
        , pIndex,       pIndexSP
        , pVar,         pVarSP
        , pTok,         pTokSP
        , pTokAs,       pTokAsSP
        , pOpSP
        , pOpVarSP)
where
import DDC.Base.Pretty
import DDC.Core.Module
import DDC.Core.Exp
import DDC.Core.Lexer.Tokens
import DDC.Base.Parser                  ((<?>), SourcePos)
import qualified DDC.Base.Parser        as P


-- | A parser of core language tokens.
type Parser n a
        = P.Parser (Tok n) a


-- | Parse a module name.                               
--   
---  ISSUE #273: Handle hierarchical module names.
--      Accept hierachical names, and reject hashes at the end of a name.
--      Hashes can be at the end of constructor name, but not module names.
pModuleName :: Pretty n => Parser n ModuleName
pModuleName = P.pTokMaybe f
 where  f (KN (KCon n)) = Just $ ModuleName [renderPlain $ ppr n]
        f _             = Nothing


-- | Parse a qualified variable or constructor name.
pQualName :: Pretty n => Parser n (QualName n)
pQualName
 = do   mn      <- pModuleName
        pTok KDot
        n       <- pName
        return  $ QualName mn n


-- | Parse a constructor or variable name.
pName :: Parser n n
pName   = P.choice [pCon, pVar]


-- | Parse a builtin named `WbCon`
pWbCon :: Parser n WbCon
pWbCon  = P.pTokMaybe f
 where  f (KA (KWbConBuiltin wb)) = Just wb
        f _                       = Nothing


-- | Parse a builtin named `WbCon`
pWbConSP :: Parser n (WbCon, SourcePos)
pWbConSP = P.pTokMaybeSP f
 where  f (KA (KWbConBuiltin wb)) = Just wb
        f _                       = Nothing


-- | Parse a constructor name.
pCon    :: Parser n n
pCon    = P.pTokMaybe f
 where  f (KN (KCon n)) = Just n
        f _             = Nothing


-- | Parse a constructor name.
pConSP    :: Parser n (n, SourcePos)
pConSP    = P.pTokMaybeSP f
 where  f (KN (KCon n)) = Just n
        f _             = Nothing


-- | Parse a literal
pLit :: Parser n n
pLit    = P.pTokMaybe f
 where  f (KN (KLit n)) = Just n
        f _             = Nothing


-- | Parse a literal, with source position.
pLitSP :: Parser n (n, SourcePos)
pLitSP  = P.pTokMaybeSP f
 where  f (KN (KLit n)) = Just n
        f _             = Nothing


-- | Parse a variable.
pVar :: Parser n n
pVar    =   P.pTokMaybe f
        <?> "a variable"
 where  f (KN (KVar n))         = Just n
        f _                     = Nothing


-- | Parse a variable, with source position.
pVarSP :: Parser n (n, SourcePos)
pVarSP  =   P.pTokMaybeSP f
        <?> "a variable"
 where  f (KN (KVar n))         = Just n
        f _                     = Nothing


-- | Parse a deBruijn index
pIndex :: Parser n Int
pIndex  =   P.pTokMaybe f
        <?> "an index"
 where  f (KA (KIndex i))       = Just i
        f _                     = Nothing


-- | Parse a deBruijn index, with source position.
pIndexSP :: Parser n (Int, SourcePos)
pIndexSP  =   P.pTokMaybeSP f
        <?> "an index"
 where  f (KA (KIndex i))       = Just i
        f _                     = Nothing


-- | Parse an infix operator.
pOpSP    :: Parser n (String, SourcePos)
pOpSP    = P.pTokMaybeSP f
 where  f (KA (KOp str))  = Just str
        f _               = Nothing


-- | Parse an infix operator used as a variable.
pOpVarSP :: Parser n (String, SourcePos)
pOpVarSP = P.pTokMaybeSP f
 where  f (KA (KOpVar str))  = Just str
        f _                  = Nothing


-- | Parse an atomic token.
pTok :: TokAtom -> Parser n ()
pTok k     = P.pTok (KA k)


-- | Parse an atomic token, yielding its source position.
pTokSP :: TokAtom -> Parser n SourcePos
pTokSP k   = P.pTokSP (KA k)


-- | Parse an atomic token and return some value.
pTokAs :: TokAtom -> a -> Parser n a
pTokAs k x = P.pTokAs (KA k) x


-- | Parse an atomic token and return source position and value.
pTokAsSP :: TokAtom -> a -> Parser n (a, SourcePos)
pTokAsSP k x = P.pTokAsSP (KA k) x


