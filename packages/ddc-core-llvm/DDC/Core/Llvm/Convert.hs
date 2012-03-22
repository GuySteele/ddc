
module DDC.Core.Llvm.Convert
        (convertModule)
where
import DDC.Llvm.Attr
import DDC.Llvm.Instr
import DDC.Llvm.Function
import DDC.Llvm.Module
import DDC.Core.Llvm.Runtime.Alloc
import DDC.Core.Llvm.Runtime.Object
import DDC.Core.Llvm.Convert.Type
import DDC.Core.Llvm.Platform
import DDC.Core.Llvm.LlvmM
import DDC.Core.Compounds
import DDC.Type.Compounds
import Data.Sequence                            (Seq, (<|), (|>), (><))
import Data.Map                                 (Map)
import qualified DDC.Core.Sea.Output.Name       as E
import qualified DDC.Core.Sea.Output.Env        as E
import qualified DDC.Core.Module                as C
import qualified DDC.Core.Exp                   as C
import qualified DDC.Base.Pretty                as P
import qualified Data.Map                       as Map
import qualified Data.Sequence                  as Seq
import qualified Data.Foldable                  as Seq
import Control.Monad.State.Strict               (evalState)
import Control.Monad.State.Strict               (gets)
import Control.Monad
import Data.Maybe

-- Module ---------------------------------------------------------------------
convertModule :: C.Module () E.Name -> Module
convertModule mm
 = let  platform        = platform32
        prims           = primGlobals platform
        state           = llvmStateInit platform prims
   in   evalState (llvmOfModuleM mm) state


llvmOfModuleM 
        :: C.Module () E.Name 
        -> LlvmM Module

llvmOfModuleM mm@(C.ModuleCore{})
 | [C.LRec bxs]         <- C.moduleLets mm   
 = do   platform        <- gets llvmStatePlatform
        functions       <- mapM (uncurry (llvmFunctionOfSuper)) bxs
        return  $ Module 
                { modComments   = []
                , modAliases    = [aObj platform]
                , modGlobals    = []
                , modFwdDecls   = []
                , modFuncs      = functions }

 | otherwise    = die "invalid module"


primGlobals :: Platform -> Map String Var
primGlobals platform
        = Map.fromList
        [ ( "malloc"
          , Var (NameGlobal "malloc")
                (convType platform (E.tNat `tFunPE` E.tPtr E.tObj))) ]


-- Super ----------------------------------------------------------------------
-- | Convert a top-level supercombinator to LLVM.
llvmFunctionOfSuper 
        :: C.Bind E.Name 
        -> C.Exp () E.Name 
        -> LlvmM Function

llvmFunctionOfSuper (C.BName n tSuper) x
 | Just (bsParam, xBody)     <- takeXLams x
 = do   platform        <- gets llvmStatePlatform

        -- Split off the argument and result types.
        let (tsArgs, tResult)       
                = takeTFunArgResult tSuper

        let params      = map (llvmParameterOfType platform) tsArgs
        let align       = AlignBytes (platformFunctionAlignBytes platform)

        -- Declaration of the super.
        let decl 
                = FunctionDecl 
                { declName               = P.renderPlain $ P.ppr n
                , declLinkage            = External
                , declCallConv           = CC_Ccc
                , declReturnType         = convType platform tResult
                , declParamListType      = FixedArgs
                , declParams             = params
                , declAlign              = align }

        label   <- newUniqueLabel "entry"
        blocks  <- llvmBlocksOfBody Seq.empty label Seq.empty xBody

        return  $ Function
                { functionDecl           = decl
                , functionParams         = map llvmNameOfParam bsParam
                , functionAttrs          = [] 
                , functionSection        = SectionAuto
                , functionBlocks         = Seq.toList blocks }

llvmFunctionOfSuper _ _
        = die "invalid super"


-- | Take the string name to use for a function parameter.
llvmNameOfParam :: C.Bind E.Name -> String
llvmNameOfParam bb
 = case bb of
        C.BName n _     -> P.renderPlain $ P.ppr n
        _               -> die "invalid parameter name"


-- Body -----------------------------------------------------------------------
llvmBlocksOfBody 
        :: Seq Block            -- ^ Previous blocks.
        -> Label                -- ^ Id of current block.
        -> Seq Instr            -- ^ Instrs in current block.
        -> C.Exp () E.Name      -- ^ Expression being converted.
        -> LlvmM (Seq Block)    -- ^ Final blocks of function body.

llvmBlocksOfBody blocks label instrs xx
 = do   platform        <- gets llvmStatePlatform
        case xx of

         -- End of function body must explicitly pass control.
         C.XApp{}
          |  Just (E.NamePrim p, xs)           <- takeXPrimApps xx
          ,  E.PrimControl E.PrimControlReturn <- p
          ,  [C.XType _t, x]                   <- xs
          ,  Just x'                           <- takeAtomX platform x
          -> return  $   blocks 
                     |>  Block label (instrs |> IReturn (Just x'))

         -- Variable assignment.
         C.XLet _ (C.LLet C.LetStrict (C.BName (E.NameVar str) t) x1) x2
          -> do t'       <- convTypeM t
                let dst  = Var (NameLocal str) t'
                instrs'  <- llvmGetResult platform dst x1
                llvmBlocksOfBody blocks label (instrs >< instrs') x2

         -- Non-binding statment.
         C.XLet _ (C.LLet C.LetStrict (C.BNone t) x1) x2
          | isVoidT t
          -> do instrs'   <- convStmtM platform x1
                llvmBlocksOfBody blocks label (instrs >< instrs')   x2

         -- Case statement.
         C.XCase _ x1 alts
          | Just x1'@(Var{})    <- takeLocalV platform x1
          -> do altResults      <- mapM convAltM alts

                let altTable    = mapMaybe takeAltCase altResults
                let altBlocks   = join $ fmap altResultBlocks $ Seq.fromList altResults

                let switchBlock = Block label
                                $ instrs |> ISwitch (XVar x1') (Label "foo") altTable

                return  $ switchBlock <| altBlocks


         -- TODO: Debugging only
         _ -> return $  blocks
                    |> Block label (instrs |> IUnreachable)

         -- die "invalid body statement"


-- | Check whether this is the Void# type.
isVoidT :: C.Type E.Name -> Bool
isVoidT (C.TCon (C.TyConBound (C.UPrim (E.NamePrimTyCon E.PrimTyConVoid) _))) = True
isVoidT _ = False


-- Alt ------------------------------------------------------------------------
convAltM :: C.Alt () E.Name -> LlvmM AltResult
convAltM aa
 = case aa of
        C.AAlt C.PDefault x
         -> do  label   <- newUniqueLabel "default"
                blocks  <- llvmBlocksOfBody Seq.empty label Seq.empty x
                return  $  AltDefault label blocks

        C.AAlt (C.PData u []) x
         -> do  label   <- newUniqueLabel "alt"
                blocks  <- llvmBlocksOfBody Seq.empty label Seq.empty x
                let lit =  convPatBound u
                return  $  AltCase lit label blocks

        _ -> error "convAltM: sorry"


convPatBound :: C.Bound E.Name -> Lit
convPatBound _
        = LitUndef (TInt 32)


data AltResult 
        = AltDefault        Label (Seq Block)
        | AltCase       Lit Label (Seq Block)


altResultBlocks :: AltResult -> Seq Block
altResultBlocks aa
 = case aa of
        AltDefault _ blocks     -> blocks
        AltCase _ _  blocks     -> blocks


takeAltCase :: AltResult -> Maybe (Lit, Label)
takeAltCase (AltCase lit label _)       = Just (lit, label)
takeAltCase _                           = Nothing


-- Exp ------------------------------------------------------------------------
llvmGetResult
        :: Platform
        -> Var  
        -> C.Exp () E.Name
        -> LlvmM (Seq Instr)

llvmGetResult _  dst (C.XVar _ (C.UName (E.NameVar str) t))
 = do   t'      <- convTypeM t
        return  $ Seq.singleton 
                $ IStore (XVar dst) (XVar (Var (NameLocal str) t'))

llvmGetResult pp dst xx@C.XApp{}
        -- Primitive operation.
        | Just (E.NamePrim p, args)       <- takeXPrimApps xx
        = convPrimCallM pp dst p args

        -- Super call.
        | xFun : xsArgs         <- takeXApps xx
        , C.XVar _ b            <- xFun
        , Just (Var nFun _)     <- takeGlobalV pp xFun
        , (_, tResult)          <- takeTFunArgResult $ typeOfBound b
        , Just xsArgs'          <- sequence $ map (takeAtomX pp) xsArgs
        = return 
                $ Seq.singleton
                $ ICall (Just dst) CallTypeStd (convType pp tResult) nFun xsArgs' []

llvmGetResult _ _ xx
        = return $ Seq.singleton 
        $ IComment [ "llvmGetResult: cannot convert " ++ show xx ]


-- Prim call ------------------------------------------------------------------
-- | Convert a primitive call to LLVM.
convPrimCallM 
        :: Show a 
        => Platform
        -> Var 
        -> E.Prim 
        -> [C.Exp a E.Name] 
        -> LlvmM (Seq Instr)

convPrimCallM pp dst p xs
 = case p of
        E.PrimStore (E.PrimStoreAllocData E.PrimStoreLayoutRaw)
         | [xTag, xSize]        <- xs
         , Just tag             <- takeTag xTag
         , Just size            <- takeNat xSize
         -> allocDataRaw dst tag size

        E.PrimCast (E.PrimCastNatToInt bitsInt)
         | [xVal]               <- xs
         , Just val             <- takeAtomX pp xVal
         -> let bitsNat = 8 * platformAddrBytes pp
            in  return 
                 $ Seq.singleton
                 $ if      bitsNat > fromIntegral bitsInt
                   then IConv dst ConvTrunc val
                   else if bitsNat < fromIntegral bitsInt
                   then IConv dst ConvSext  val
                   else ISet  dst val

        E.PrimString (E.PrimStringShowInt bitsInt)
         |  [xVal]              <- xs
         ,  Just val            <- takeAtomX pp xVal
         -> return
                $ Seq.singleton
                $ ICall (Just dst)
                        CallTypeStd 
                        (tPtr (TInt 8)) 
                        (NameGlobal $ "showInt" ++ show bitsInt)
                        [val] []

        _ -> return $ Seq.singleton 
          $ IComment ["convPrimCallM: cannot convert " ++ show (p, xs)]


-- Stmt -----------------------------------------------------------------------
convStmtM :: Platform -> C.Exp () E.Name -> LlvmM (Seq Instr)
convStmtM pp xx
 = case xx of
        C.XApp{}
         |  C.XVar _ (C.UPrim (E.NamePrim p) t) : xs <- takeXApps xx
         -> convPrimStmtM pp p t xs

        _ -> error "convStmtM: sorry"


-- | Convert a primitive statement to LLvM.
convPrimStmtM 
        :: Show a 
        => Platform
        -> E.Prim 
        -> C.Type E.Name
        -> [C.Exp a E.Name] 
        -> LlvmM (Seq Instr)

convPrimStmtM pp prim tPrim xs
 = case prim of
        E.PrimStmt E.PrimStmtWrite
         |  [C.XType _t, x1, x2] <- xs
         ,  Just x1'            <- takeAtomX pp x1
         ,  Just x2'            <- takeAtomX pp x2
         -> return $ Seq.singleton
                   $ IStore x1' x2'

        E.PrimIO op
         | Just xs'             <- sequence $ map (takeAtomX pp) xs
         , (_, tResult)         <- takeTFunArgResult tPrim
         , tResult'             <- convType pp tResult
         , name                 <- nameOfPrimIO op
         -> return $ Seq.singleton
                   $ ICall Nothing  CallTypeStd
                           tResult' name xs' []

        -- debugging
        _ -> return $ Seq.singleton IUnreachable

nameOfPrimIO :: E.PrimIO -> Name
nameOfPrimIO pp
 = case pp of
        E.PrimIOPutStr          -> NameGlobal "putStr"
        E.PrimIOPutStrLn        -> NameGlobal "putStrLn"



-- Utils ----------------------------------------------------------------------
-- | Take a variable or literal from an expression.
--   Returned literals are also represented as `Var`.
takeAtomX :: Platform -> C.Exp a E.Name -> Maybe Exp
takeAtomX pp xx
 = case xx of
        C.XVar _ (C.UName (E.NameVar str) t)
         -> Just $ XVar (Var (NameLocal str) (convType pp t))

        C.XCon _ (C.UPrim (E.NameTag tag) t)
         -> Just $ XLit (LitInt (convType pp t) tag)

        C.XCon _ (C.UPrim (E.NameNat nat) t)
         -> Just $ XLit (LitInt (convType pp t) nat)

        _ -> Nothing


-- | Take a variable from an expression as a local var, if any.
takeLocalV  :: Platform -> C.Exp a E.Name -> Maybe Var
takeLocalV pp xx
 = case xx of
        C.XVar _ (C.UName (E.NameVar str) t)
          -> Just $ Var (NameLocal str) (convType pp t)
        _ -> Nothing


-- | Take a variable from an expression as a local var, if any.
takeGlobalV  :: Platform -> C.Exp a E.Name -> Maybe Var
takeGlobalV pp xx
 = case xx of
        C.XVar _ (C.UName (E.NameVar str) t)
          -> Just $ Var (NameGlobal str) (convType pp t)
        _ -> Nothing


-- | Take an integer tag from an expression, if any.
takeTag :: C.Exp a E.Name -> Maybe Integer
takeTag xx
 = case xx of
        C.XCon _ (C.UPrim (E.NameTag tag) _)    -> Just tag
        _                                       -> Nothing


-- | Take an natural number from an expression, if any.
takeNat :: C.Exp a E.Name -> Maybe Integer
takeNat xx
 = case xx of
        C.XCon _ (C.UPrim (E.NameNat nat) _)    -> Just nat
        _                                       -> Nothing
