
-- | Represents a worker thread that an be given a job 
--	to do and returns its result when done.
module Util.Control.Dispatch.Worker
	( Worker (..)
	, workerIsFree
	, setWorkerAsFree
	, takeFirstFreeWorker
	, takeWorkerResult
	, takeFirstWorkerResult )
where
import Util
import Control.Concurrent
import Data.Function

-- | Represents the state of a worker thread as visible by the dispatcher
data Worker job result
	= Worker 
		{ workerThreadId 	:: ThreadId
		, workerIsBusy		:: Bool
		, workerTestVar		:: MVar (job, [job])			-- job, children
		, workerResultVar	:: MVar (job, [job], result) }		-- job, children, result
	
instance Eq (Worker job result) where
	(==)		= (==) `on` workerThreadId 

instance Ord (Worker job result) where
	compare w1 w2	= compare (workerThreadId w1) (workerThreadId w2)


-- | Set the worker as free
setWorkerAsFree :: Worker job result -> Worker job result
setWorkerAsFree worker
	= worker { workerIsBusy	= False }


-- | Check if a worker is free to have work sent to it.
--	A worker is free if its test MVar is empty
--	and it's not marked as busy.
--
workerIsFree 
	:: Worker job result 
	-> IO Bool

workerIsFree worker
	| workerIsBusy worker
	= return False

	| otherwise
	= isEmptyMVar $ workerTestVar worker


-- | Take the first free worker from this list
takeFirstFreeWorker 
	:: [Worker job result] 
	-> IO (Maybe (Worker job result))
	
takeFirstFreeWorker workers
 = do	free	<- mapM workerIsFree workers
	let workFree	
		= zipWith 
			(\w f -> if f then Just w else Nothing)
			workers
			free
	return	$ takeFirstJust workFree



-- | Try to take the result of this worker thread.
--	If it hasn't posted a result yet then returns Nothing.
takeWorkerResult 
	:: Worker job result
	-> IO (Maybe (job, [job], result))
	
takeWorkerResult worker
 	= tryTakeMVar (workerResultVar worker)


-- | Take the first worker from the list which has an available result.
takeFirstWorkerResult 
	:: [Worker job result] 
	-> IO (Maybe 
		( Worker job result
		, job
		, [job]
		, result))

takeFirstWorkerResult []	
 = 	return Nothing

takeFirstWorkerResult (w:ws)
 = do	mResult	<- takeWorkerResult w
	case mResult of
	 Nothing			-> takeFirstWorkerResult ws
	 Just (job, children, res)	-> return $ Just (w, job, children, res)
	
