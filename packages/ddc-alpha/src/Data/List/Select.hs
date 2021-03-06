{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
module Data.List.Select
	( test_UtilDataListSelect
	, lookupBy
	, eachAndOthers
	, collate
	, interslurp)
where
import Data.List
import Util.Test.Check
import qualified Data.Map	as Map

test_UtilDataListSelect
	= [ test_eachAndOthers_total ]


-- | General lookup function, using this equality test
lookupBy :: (a -> a -> Bool) ->	a -> [(a, b)] 	-> Maybe b
lookupBy _ _ []		= Nothing
lookupBy f a  ((k,d):xs)
	| f a k		= Just d
	| otherwise	= lookupBy f a xs


-- | Takes a list, 
--	returns a list of pairs (x, xs) 
--		where x is an element of the list
--		and   xs is a list of the the other elements
--
--  eg: eachAndOthers [1, 2, 3, 4]
--		= [(1, [2, 3, 4]), (2, [1, 3, 4]), (3, [1, 2, 4]), (4, [1, 2, 3])]
--
eachAndOthers :: [a] -> [(a, [a])]
eachAndOthers  xx		= eachAndOthers' xx []
eachAndOthers' []	_	= []
eachAndOthers' (x:xs) prev 	
	= (x, prev ++ xs) : eachAndOthers' xs (prev ++ [x])


-- @ The whole list is present in each output elem
test_eachAndOthers_total
	= testBool "eachAndOthers_total" 
	$ \(xx :: [Int]) 
	-> all 	(== (nub $ sort xx)) 
		[ nub $ sort (y:ys) | (y, ys) <- eachAndOthers xx]


-- | Collate a list of pairs on the first element
--	collate [(0, 1), (0, 2), (3, 2), (4, 5), (3, 1)] = [(0, [1, 2]), (3, [2, 1]), (4, [5])]
collate :: Ord a => [(a, b)] -> [(a, [b])]
collate	xx	
 	= Map.toList 
	$ foldr (\(k, v) m -> 
			Map.insertWith 
				(\x xs -> x ++ xs) 
				k [v] m) 
		Map.empty 
		xx


-- | Inverse of intersperse (sorta)
--   Takes every second (internal) element of a list
--   interslurp [1, 2, 3, 4, 5, 6] = [2, 4]
interslurp :: [a] 	-> [a]
interslurp []		= []
interslurp (_:[])	= []
interslurp (_:_:[])	= []
interslurp (_:b:xs)  	= b : interslurp xs

