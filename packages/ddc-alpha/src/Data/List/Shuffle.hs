{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
-- | Sorting and Shuffling
module Data.List.Shuffle
	( test_UtilDataListShuffle
	, rotate
	, partitionBy
	, partitionBySort)	
where
import Data.List
import Data.Maybe
import Util.Test.Check

test_UtilDataListShuffle
	= [test_rotate_inv]


-- Shuffling / Sorting ----------------------------------------------------------------------------
-- | Rotate a list this many elements right
--	eg rotate 1 [1, 2, 3, 4] == [2, 3, 4, 1]
rotate :: Int -> [a] 	-> [a]
rotate n xx 	
 	| n == 0	= xx

 	| n >  0	
	, len		<- length xx
	= take len 
		$ drop (n `mod` len) 
		$ cycle xx

 	| n <  0	
	, len		<- length xx
	= take len 
		$ drop (length xx + (n `mod` len)) 
		$ cycle xx

	| otherwise
	= error "Util.Data.List.Shuffle.rotate: no match"

-- @ We can rotate the list back, also for (abs n) > length of list
test_rotate_inv
	= testBool2 "rotate_inv"
	$ \(xx :: [Int]) (n :: Int)
	-> xx == rotate (- n) (rotate n xx)


-- | Separate out this list into bins. 
--   An element goes in the bin if it matches the corresponding predicate.
partitionBy :: 	[(a -> Bool)] -> [a] -> ([[a]], [a])
partitionBy fs xx 
 = let	(bins, rest)	= mapAccumL (partitionBy1 fs) (replicate (length fs) []) xx
   in	( map reverse bins
        , catMaybes rest)
	
-- | Place an element on the head of the bin which matches the corresponding predicate
--	If no bins match the element goes on the floor.
partitionBy1 :: [(a -> Bool)] -> [[a]] -> a -> ([[a]], Maybe a)
partitionBy1 fs bins x 
	= partitionBy1' fs [] bins x

-- no predicates matched, drop the element on the floor
partitionBy1'  []      binPrev []	x
	= (binPrev, Just x)

-- ran out of functions before we ran out of bins
--	just say we couldn't match anything
partitionBy1'	[]	binPrev binsRest 	x
	= ( binPrev ++ binsRest
	  , Just x)	

-- ran out of bins before we ran out of functions
--	just make a new bin and carry on
partitionBy1'  ff  	binPrev []  	x
	= partitionBy1' ff binPrev [[]] x

partitionBy1'  (f:fs)  binPrev (bin:binRest)  x

	-- predicate matched, place the element in the current bin
	| f x
	= ( binPrev ++ [x:bin] ++ binRest
	  , Nothing)
	
	-- predicate failed, move on to the next bin.
	| otherwise
	= partitionBy1' fs (binPrev ++ [bin]) binRest x


-- | Do a partitionBy then concat the results together into a single list.
partitionBySort :: [(a -> Bool)] -> [a] -> [a]
partitionBySort fs xx
 = let	(bins, rest)	= partitionBy fs xx
   in	(concat bins ++ rest)


