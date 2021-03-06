module DDC.Type.Transform.Crush
        ( crushSomeT
        , crushEffect )
where
import DDC.Type.Predicates
import DDC.Type.Compounds
import DDC.Type.Transform.Trim
import DDC.Type.Exp
import qualified DDC.Type.Sum   as Sum
import Data.Maybe


-- | Crush compound effects and closure terms.
--   We check for a crushable term before calling crushT because that function
--   will recursively crush the components. 
--   As equivT is already recursive, we don't want a doubly-recursive function
--   that tries to re-crush the same non-crushable type over and over.
--
crushSomeT :: Ord n => Type n -> Type n
crushSomeT tt
 = {-# SCC crushSomeT #-}
   case tt of
        (TApp (TCon tc) _)
         -> case tc of
                TyConSpec    TcConDeepRead   -> crushEffect tt
                TyConSpec    TcConDeepWrite  -> crushEffect tt
                TyConSpec    TcConDeepAlloc  -> crushEffect tt

                -- If a closure is miskinded then 'trimClosure' 
                -- can return Nothing, so we just leave the term untrimmed.
                TyConSpec    TcConDeepUse    -> fromMaybe tt (trimClosure tt)

                TyConWitness TwConDeepGlobal -> crushEffect tt
                _                            -> tt

        _ -> tt


-- | Crush compound effect terms into their components.
--
--   This is like `trimClosure` but for effects instead of closures.
-- 
--   For example, crushing @DeepRead (List r1 (Int r2))@ yields @(Read r1 + Read r2)@.
--
crushEffect :: Ord n => Effect n -> Effect n
crushEffect tt
 = {-# SCC crushEffect #-}
   case tt of
        TVar{}          -> tt
        TCon{}          -> tt
        TForall b t
         -> TForall b (crushEffect t)

        TSum ts         
         -> TSum
          $ Sum.fromList (Sum.kindOfSum ts)   
          $ map crushEffect
          $ Sum.toList ts

        TApp t1 t2
         -- Head Read.
         |  Just (TyConSpec TcConHeadRead, [t]) <- takeTyConApps tt
         -> case takeTyConApps t of

             -- Type has a head region.
             Just (TyConBound _ k, (tR : _)) 
              |  (k1 : _, _) <- takeKFuns k
              ,  isRegionKind k1
              -> tRead tR

             -- Type has no head region.
             -- This happens with  case () of { ... }
             Just (TyConSpec  TcConUnit, [])    -> tBot kEffect
             Just (TyConBound _ _,       _)     -> tBot kEffect

             _ -> tt

         -- Deep Read.
         -- See Note: Crushing with higher kinded type vars.
         | Just (TyConSpec TcConDeepRead, [t]) <- takeTyConApps tt
         -> case takeTyConApps t of
             Just (TyConBound _ k, ts)
              | (ks, _)  <- takeKFuns k
              , length ks == length ts
              , Just effs       <- sequence $ zipWith makeDeepRead ks ts
              -> crushEffect $ TSum $ Sum.fromList kEffect effs

             _ -> tt

         -- Deep Write
         -- See Note: Crushing with higher kinded type vars.
         | Just (TyConSpec TcConDeepWrite, [t]) <- takeTyConApps tt
         -> case takeTyConApps t of
             Just (TyConBound _ k, ts)
              | (ks, _)  <- takeKFuns k
              , length ks == length ts
              , Just effs       <- sequence $ zipWith makeDeepWrite ks ts
              -> crushEffect $ TSum $ Sum.fromList kEffect effs

             _ -> tt 

         -- Deep Alloc
         -- See Note: Crushing with higher kinded type vars.
         | Just (TyConSpec TcConDeepAlloc, [t]) <- takeTyConApps tt
         -> case takeTyConApps t of
             Just (TyConBound _ k, ts)
              | (ks, _)  <- takeKFuns k
              , length ks == length ts
              , Just effs       <- sequence $ zipWith makeDeepAlloc ks ts
              -> crushEffect $ TSum $ Sum.fromList kEffect effs

             _ -> tt

         -- Deep Global
         -- See Note: Crushing with higher kinded type vars.
         --
         -- NOTE: We're hijacking crushEffect to work on witnesses as well.
         --       It would be better to split this into another function.
         --
         | Just (TyConWitness TwConDeepGlobal, [t]) <- takeTyConApps tt
         -> case takeTyConApps t of
             Just (TyConBound _ k, ts)
              | (ks, _)  <- takeKFuns k
              , length ks == length ts
              , Just props       <- sequence $ zipWith makeDeepGlobal ks ts
              -> crushEffect $ TSum $ Sum.fromList kWitness props

             _ -> tt 

         | otherwise
         -> TApp (crushEffect t1) (crushEffect t2)


-- | If this type has first order kind then wrap with the 
--   appropriate read effect.
makeDeepRead :: Kind n -> Type n -> Maybe (Effect n)
makeDeepRead k t
        | isRegionKind  k       = Just $ tRead t
        | isDataKind    k       = Just $ tDeepRead t
        | isClosureKind k       = Just $ tBot kEffect
        | isEffectKind  k       = Just $ tBot kEffect
        | otherwise             = Nothing


-- | If this type has first order kind then wrap with the 
--   appropriate read effect.
makeDeepWrite :: Kind n -> Type n -> Maybe (Effect n)
makeDeepWrite k t
        | isRegionKind  k       = Just $ tWrite t
        | isDataKind    k       = Just $ tDeepWrite t
        | isClosureKind k       = Just $ tBot kEffect
        | isEffectKind  k       = Just $ tBot kEffect
        | otherwise             = Nothing


-- | If this type has first order kind then wrap with the 
--   appropriate read effect.
makeDeepAlloc :: Kind n -> Type n -> Maybe (Effect n)
makeDeepAlloc k t
        | isRegionKind  k       = Just $ tAlloc t
        | isDataKind    k       = Just $ tDeepAlloc t
        | isClosureKind k       = Just $ tBot kEffect
        | isEffectKind  k       = Just $ tBot kEffect
        | otherwise             = Nothing


-- | If this type has first order kind then wrap with the 
--   appropriate read effect.
makeDeepGlobal :: Kind n -> Type n -> Maybe (Type n)
makeDeepGlobal k t
        | isRegionKind  k       = Just $ tGlobal t
        | isDataKind    k       = Just $ tDeepGlobal t
        | isClosureKind k       = Nothing
        | isEffectKind  k       = Just $ tBot kEffect
        | otherwise             = Nothing


{- [Note: Crushing with higher kinded type vars]
   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   We can't just look at the free variables here and wrap Read and DeepRead constructors
   around them, as the type may contain higher kinded type variables such as: (t a).
   Instead, we'll only crush the effect when all variable have first-order kind.
   When comparing types with higher order variables, we'll have to use the type
   equivalence checker, instead of relying on the effects to be pre-crushed.
-}
