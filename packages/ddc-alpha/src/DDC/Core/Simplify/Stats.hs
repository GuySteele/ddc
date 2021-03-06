{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
module DDC.Core.Simplify.Stats
	( Stats(..)
	, statsProgress

	, RuleCounts(..)
	, ruleCountsZero
	, countBoxing
	, countMatch)
where
import DDC.Core.Simplify.Boxing
import DDC.Core.Simplify.Match
import DDC.Main.Pretty
import Control.Monad.State.Strict
import qualified DDC.Core.Float	as Float
import Data.Map			(Map)
import qualified Data.Map	as Map

-- Stats ------------------------------------------------------------------------------------------
-- | Statistics about what happened during a pass of the simplifier.
data Stats
	= Stats
	{ -- | Stats from the let-floater
	  statsFloat		:: Maybe Float.Stats

	  -- | Counts of rule firings.
	, statsRuleCounts	:: RuleCounts }
	deriving (Show)


-- | Check the stats of a simplifier pass to see if we made any progress
statsProgress :: Stats -> Bool
statsProgress stats
 = or	[ not $ Map.null $ ruleCountsBoxing $ statsRuleCounts stats
	, not $ Map.null $ ruleCountsMatch  $ statsRuleCounts stats
	, maybe False (\s -> not $ null $ Float.statsSharedForcings  s) $ statsFloat stats
	, maybe False (\s -> not $ null $ Float.statsSharedUnboxings s) $ statsFloat stats ]


-- RuleCounts -------------------------------------------------------------------------------------
-- | Counts of rule firings.
data RuleCounts
	= RuleCounts
	{ ruleCountsBoxing	:: Map RuleBoxing Int
	, ruleCountsMatch	:: Map RuleMatch Int }
	deriving (Show)
	
ruleCountsZero 
	= RuleCounts
	{ ruleCountsBoxing	= Map.empty
	, ruleCountsMatch	= Map.empty }
	
countBoxing rule = modify $ \s -> s { ruleCountsBoxing = bumpCount rule (ruleCountsBoxing s) }
countMatch  rule = modify $ \s -> s { ruleCountsMatch  = bumpCount rule (ruleCountsMatch  s) }

bumpCount :: Ord a => a -> Map a Int -> Map a Int
bumpCount rule mp
 = Map.alter (\e -> case e of
			Nothing	-> Just 1
			Just n	-> Just (n + 1))
	     rule
	     mp


-- Pretty -----------------------------------------------------------------------------------------
instance Pretty Stats PMode where
 ppr stats
 	= vcat
	[ ppr "Simplify.Stats"
	, " * Stats from let-floater:\n"
		%> ppr (statsFloat stats)
 	, ppr " * Rule firings:"
	, vcat 	(  (pprStats $ Map.toList $ ruleCountsBoxing $ statsRuleCounts stats)
		++ (pprStats $ Map.toList $ ruleCountsMatch  $ statsRuleCounts stats)) ]
			

pprStats :: Show name => [(name, Int)] -> [Str]
pprStats stats
	= [ "   " % padL 20 (show name) % " : " % show count
		| (name, count)	<- stats]





