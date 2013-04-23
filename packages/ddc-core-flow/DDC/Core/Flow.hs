
-- | Disciple Core Flow
--
--   This is a DSL intended for optimising first order data flow programs
--   as part of the Data Parallel Haskell vectorisation pipeline.
--
module DDC.Core.Flow
        ( -- * Language profile
          profile

          -- * Names
        , Name          (..)
        , TyConFlow     (..)
        , PrimTyCon     (..)
        , PrimArith     (..)
        , PrimCast      (..)

          -- * Name Parsing
        , readName

          -- * Program Lexing
        , lexModuleString
        , lexExpString)

where
import DDC.Core.Flow.Prim
import DDC.Core.Flow.Profile
