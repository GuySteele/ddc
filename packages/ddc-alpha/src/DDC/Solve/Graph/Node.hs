{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | Node types are the simple type constraints that are stored directly in graph equivalence
--   classes. The children of a Node type are always cids. This is opposed to regular 
--   Types who's children can be more types.
--
--  HISTORY: We use to just have regular types in the graph, but its too fiddly to deal
--           with the possibility of children being either cids or more types. It's a lot
--           less buggy to keep the graph in this simpler form.
--
module DDC.Solve.Graph.Node
	( Node		(..)

	-- * Simple checks.
	, isNBot
	, isNVar
	, isNCon
	, isNApp

	-- * Substitution.
	, subNodeCidCid

	-- * Extraction.
	, cidsOfNode
	
	-- * Builtin nodes.
	, nBot
	, nRead
	, nDeepRead
	, nHeadRead
	, nWrite
	, nDeepWrite)
where
import DDC.Main.Pretty
import DDC.Var
import DDC.Type
import Data.Maybe
import Data.Set			(Set)
import Data.Map			(Map)
import qualified Data.Set	as Set
import qualified Data.Map	as Map


-- | A node type.
data Node
	= NBot
	| NCid		!ClassId
	| NVar		!Var
	| NCon		!TyCon
	| NApp		!ClassId !ClassId

	-- | Finished type schemes are added back to the type graph.
	--	We want to keep them in the graph because closure terms in other types
	--	may be refering to them, and they may still contain unquantified cids.
	| NScheme 	!Type

	-- A closure constructor. 
	-- TODO: I'm not sure if we want to convert the right of this to node form
	--       as well. We'd need a TyCon for the (NFree v) part first though.
	| NFree		!Var !Type
	
	-- | Used when the node has been involved in a type error.
	| NError
	deriving (Show, Eq)


-- Simple Checks ----------------------------------------------------------------------------------
-- | Check if a node is represents bottom.
isNBot :: Node -> Bool
isNBot nn 
 = case nn of
	NBot		-> True
	_		-> False

-- | Check if a node is an NVar.
isNVar :: Node -> Bool
isNVar nn
 = case nn of
	NVar{}	-> True
	_	-> False

-- | Check if a node is an NCon
isNCon :: Node -> Bool
isNCon nn
 = case nn of
	NCon{}	-> True
	_	-> False

-- | Check if a node is an NApp
isNApp :: Node -> Bool
isNApp nn
 = case nn of
	NApp{}	-> True
	_	-> False

	
-- Substitution -----------------------------------------------------------------------------------
-- | Substitute cids for cids in some node
subNodeCidCid :: Map ClassId ClassId -> Node -> Node
subNodeCidCid sub nn
 = case nn of
	NBot{}		-> nn
	NVar{}		-> nn
	NCon{}		-> nn

	NCid cid
	 -> NCid  (fromMaybe cid  (Map.lookup cid sub))

	NApp cid1 cid2
	 -> NApp  (fromMaybe cid1 (Map.lookup cid1 sub))
		  (fromMaybe cid2 (Map.lookup cid2 sub))
		
	NScheme t
	 -> NScheme $ subCidCid_everywhere sub t
	
	NError{}	-> nn
	
	NFree v t	
	 -> NFree v $ subCidCid_everywhere sub t


-- Extraction -------------------------------------------------------------------------------------
-- | Get the set of all ClassIds in a node.
cidsOfNode :: Node -> Set ClassId
cidsOfNode nn
 = case nn of
	NBot		-> Set.empty
	NCid cid	-> Set.singleton cid
	NVar{}		-> Set.empty
	NCon{}		-> Set.empty
	NApp c1 c2	-> Set.fromList [c1, c2]
	NError{}	-> Set.empty
	NScheme t	-> freeCids t
	NFree _ t	-> freeCids t


-- Builtins ---------------------------------------------------------------------------------------
nBot		= NBot

nRead		= NCon $ TyConEffect TyConEffectRead
		$ KFun kRegion kEffect

nDeepRead	= NCon $ TyConEffect TyConEffectDeepRead
		$ KFun kValue kEffect

nHeadRead	= NCon $ TyConEffect TyConEffectHeadRead
		$ KFun kValue kEffect

nWrite		= NCon $ TyConEffect TyConEffectWrite
		$ KFun kRegion kEffect

nDeepWrite	= NCon $ TyConEffect TyConEffectDeepWrite
		$ KFun kValue kEffect


-- Instances --------------------------------------------------------------------------------------
instance Pretty Node PMode where
 ppr nn
  = case nn of
	NBot		-> ppr "NBot"
	NCid cid	-> ppr cid
	NVar v		-> ppr v
	NCon tc		-> ppr tc
	NApp cid1 cid2	-> parens $ cid1 %% cid2
	NScheme t	-> "NScheme " % t
	NFree v t	-> "NFree " % v % " :: " % t
	_		-> ppr $ show nn

