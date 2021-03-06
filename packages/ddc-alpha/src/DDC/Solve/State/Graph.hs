
-- | Wrappers for type graph operations. 
--   This module just makes them nicer to use in the `SquidM` monad, the real code is in "DDC.Solve.Graph".
module DDC.Solve.State.Graph
	( module DDC.Solve.Graph
	, lookupClass
	, lookupCidOfVar
	, kindOfClass
	, allocClass
	, ensureClassWithVar
	, modifyClass
	, updateClass
	, delSingleFetter
	, delMultiFetter
	, activateClass
	, clearActive
	, foldClasses
	, addNodeToClass
	, addAliasForClass)
where
import DDC.Solve.Location
import DDC.Solve.State.Base
import DDC.Solve.State.Squid
import DDC.Solve.Graph
import DDC.Type
import DDC.Var
import Data.Array.IO
import Control.Monad.Trans
import Control.Monad
import Data.Set			(Set)
import qualified Data.Map	as Map


-- | Lookup a class from the graph.
lookupClass :: ClassId -> SquidM (Maybe Class)
lookupClass cid
 = do	graph	<- getsRef stateGraph
 	liftIO $ lookupClassFromGraph cid graph


-- | Lookup the cid corresponding to this type variable.
lookupCidOfVar :: Var -> SquidM (Maybe ClassId)
lookupCidOfVar v
 = do	graph	<- getsRef stateGraph
	case Map.lookup v (graphVarToClassId graph) of
	 Nothing	-> return Nothing
	 Just cid	
	  -> do	cid'	<- liftIO $ sinkClassIdOfGraph cid graph
	  	return	$ Just cid'


-- | Get the kind of a class in the graph.
kindOfClass :: ClassId -> SquidM Kind
kindOfClass cid
 = do	Just c	<- lookupClass cid
 	return	$ classKind c


-- | Allocate a new class into the type graph.
allocClass :: Kind -> TypeSource -> SquidM ClassId
allocClass kind src
 = do	graph		<- getsRef stateGraph
	(cid, graph')	<- liftIO $ addClassToGraph (emptyClass kind src) graph
	writesRef stateGraph graph'
	return cid


-- | If there is already a class for this variable then return that
--   otherwise make a new one containing this var.
ensureClassWithVar :: Kind -> TypeSource -> Var	-> SquidM ClassId
ensureClassWithVar kind src var
 = do	mCid		<- lookupCidOfVar var
   	case mCid of
   	 Just cid	-> return cid
	 Nothing 
	  -> do	cid	<- allocClass kind src 
		addAliasForClass cid kind src var
	     	return cid


-- | Modify a class in the graph, and activate it.
modifyClass :: ClassId -> (Class -> Class) -> SquidM ()
modifyClass cid f
 = do	graph	<- getsRef stateGraph
	liftIO $ modifyClassInGraph True cid graph f


-- | Update a class in the graph, and activate it.
updateClass :: Bool -> ClassId -> Class -> SquidM ()
updateClass activate cid cls
 = do	graph	<- getsRef stateGraph
	liftIO $ modifyClassInGraph activate cid graph (\_ -> cls)


-- | Delete a SPTC Fetter from a class.
delSingleFetter :: ClassId -> Var -> SquidM ()
delSingleFetter cid v
 = 	modifyClass cid 
 	 $ \cls -> cls { classFetters = Map.delete v (classFetters cls) }
	

-- | Delete a fetter class from the type graph.
--
--   Note: This class *cannot* be re-used because it may have been deleted due to a MPTC
--	   being crushed out. Other nodes will still refer to this one, and Type.Trace 
--	   treats the ClassFetterDeleted as generating no constraints.
delMultiFetter :: ClassId -> SquidM ()
delMultiFetter cid
 = do	graph	<- getsRef stateGraph
	liftIO $ delFetterFromGraph cid graph
	

-- | Activate a class, and any MPTC's acting on it.
activateClass :: ClassId -> SquidM ()
activateClass cid
 = do	graph	<- getsRef stateGraph
	liftIO 	$ activateClassOfGraph cid graph


-- | Clear the set of active classes.
clearActive ::	SquidM (Set ClassId)
clearActive
 = do	graph	<- getsRef stateGraph
	liftIO	$ clearActiveClassesOfGraph graph


-- | Fold a function through all the classes in the type graph.
foldClasses :: (a -> Class -> SquidM a) -> a -> SquidM a
foldClasses fun x
 = do  	graph		<- getsRef stateGraph
	classes		<- liftIO $ getElems $ graphClass graph
	foldM fun x classes  


-- | Add a new node constraint to a class in the graph, and activate it.
addNodeToClass :: ClassId -> Kind -> TypeSource -> Node -> SquidM ()
addNodeToClass cid kind src node
 = do	graph	<- getsRef stateGraph
	graph'	<- liftIO $ addNodeToClassInGraph cid kind src node graph
	writesRef stateGraph graph'


-- | Add an alias for a class.
--   An alias is a name that identifies the class. There can be many aliases 
--   for a given class, but only one ''canonical'' name.
addAliasForClass :: ClassId -> Kind -> TypeSource -> Var -> SquidM ()
addAliasForClass cid kind src var
 = do	graph	<- getsRef stateGraph
	graph'	<- liftIO $ addAliasForClassInGraph cid kind src var graph
	writesRef stateGraph graph'


