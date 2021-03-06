
-- | Rewrite code so that it stores pointers to boxed objects on the GC slot stack
--	instead of directly in C variables. We do this so that the garbage collector
--	can work out the root set if called.
module Sea.Slot
	(slotTree)
where
import Util
import Shared.VarUtil
import Sea.Plate.Trans
import DDC.Sea.Exp
import DDC.Var
import qualified DDC.Core.Glob	as C
import qualified Shared.Unique	as Unique
import qualified Data.Map	as Map


-- | Rewrite code in this tree to use the GC slot stack.
slotTree
	:: Tree () 		-- ^ source tree.
	-> Tree () 		-- ^ prototypes of imported functions.
	-> C.Glob		-- ^ header glob, used to get arities of supers.
	-> C.Glob		-- ^ source glob, TODO: refactor this to use sea glob
	-> Tree ()

slotTree tree eHeader cgHeader cgSource
 	= evalState (mapM (slotP cgHeader cgSource) tree)
 	$ VarId Unique.seaSlot 0

-- | Rewrite code in this top level thing to use the GC slot stack.
slotP 	:: C.Glob		-- ^ header glob
	-> C.Glob		-- ^ source glob
	-> Top ()
	-> VarGenM (Top ())

slotP cgHeader cgSource p
 = case p of
 	PSuper v args retT ss
	 -> do	(ssAuto, ssArg, ssR, slotCount)
	 		<- slotSS cgHeader cgSource args ss

		let Just (SReturn x) = takeLast ssR
		retVar		<- newVarN NameValue

		let retBoxed		= typeIsBoxed retT
		let hasSlots		= slotCount > 0

		return	$ PSuper v args retT
			$  (nub ssAuto)
			++ (if retBoxed	&& hasSlots 	then [ SAuto	retVar retT] 		else [])
			++ (if hasSlots			then [ SEnter	slotCount  ] 		else [])
			++ ssArg
			++ init ssR
			++ (if retBoxed && hasSlots	then [ SAssign	(XVar (NAuto retVar) retT) retT x ]	else [])
			++ (if hasSlots			then [ SLeave	slotCount ] 		else [])
			++ (if retBoxed && hasSlots
				then [ SReturn (XVar (NAuto retVar) retT) ]
				else [ SReturn x ])

	_ -> return p

-- | Rewrite the body of a supercombinator to use the GC slot stack
slotSS 	:: C.Glob		-- ^ header glob
	-> C.Glob		-- ^ source glob
	-> [(Var, Type)] 	-- ^ vars and types of the super parameters
	-> [Stmt ()] 		-- ^ statements that form the body of the super
	-> VarGenM
		( [Stmt ()]	-- code that copies the super parameters into their slots.
		, [Stmt ()]	-- code that initialises automatic variables for each local unboxed variable.
		, [Stmt ()]	-- body of the super, rewritten to use slots.
		, Int)		-- the number of GC slots used by this super.

slotSS _cgHeader _cgSource args ss
 = do
 	-- Place the managed args into GC slots.
	let (ssArg_, state0)
		= runState
			(mapM slotAssignArg args)
			slotInit

	let ssArg	= catMaybes ssArg_

	-- Create a new GC slots for vars on the LHS of an assignment.
	let (ss2, state1)
		= runState
			(mapM (transformSM slotAssignS) ss)
			state0

	-- Rewrite vars in expressions to their slots.
	let ss3	= map (transformX
			(\x -> slotifyX x (stateMap state1)))
			ss2

	-- Make automatic variables for unboxed values.
	--	In compiled tail recursive functions there may be assignments
	--	to arguments in the parameter list. These will appear in the stateAuto
	--	list, but there's no need to actually make a new auto for them.
	let ssAuto	= [ SAuto v t	| (v, t)	<- reverse
							$ stateAuto state1
					, not $ elem v	$ map fst args]

	-- Count how many slots we've used
	let slotCount	= Map.size (stateMap state1)

	return	(ssAuto, ssArg, ss3, slotCount)

slotAssignArg	(v, t)
 	| not $ typeIsBoxed t
	= return Nothing

	| otherwise
	= do
	 	ixSlot	<- newSlot
		let exp	= XVar (NSlot v ixSlot) t

		addSlotMap v exp

		return	$ Just
			$ SAssign exp t (XVar (NAuto v) t)

slotifyX 
	:: Exp  ()
	-> Map Var (Exp ())
	-> Exp  ()
	
slotifyX x m
	| XVar (NAuto v) _	<- x
	, Just exp	<- Map.lookup v m
	= exp

	-- BUGS: unboxed top level data is not a CAF
	| XVar (NCaf v) t	<- x
	, typeIsBoxed t
	= XVar (NCafPtr v) t

	| otherwise
	= x


-- SlotM ------------------------------------------------------------------------------------------
-- State monad for doing the GC slot transform.
data SlotS
	= SlotS
	{ stateMap	:: Map Var (Exp ())	-- ^ map of original variable
						--	to the XSlot expression that represents
						--	the GC slot it is stored in.

	, stateSlot	:: Int 			-- ^ new slot number generator

	, stateAuto	:: [(Var, Type)] }

slotInit
	= SlotS
	{ stateMap	= Map.empty
	, stateSlot	= 0
	, stateAuto	= [] }

type SlotM = State SlotS


--- | Create a fresh slot number
newSlot :: SlotM Int
newSlot
 = do 	slot	<- gets stateSlot
	modify (\s -> s { stateSlot = slot + 1 })
	return slot


-- | Add an entry to the slot map
addSlotMap
	:: Var
	-> Exp ()
	-> SlotM ()
addSlotMap    var    x
 =	modify (\s -> s {
 		stateMap = Map.insert var x (stateMap s) })


-- | Assign a GC slot for all variables present on the LHS of an assignment.
slotAssignS :: Stmt () -> SlotM (Stmt ())
slotAssignS ss
 = case ss of
 	SAssign (XVar (NAuto v) t) tt x
 	 | typeIsBoxed tt
	 -> do 	slotMap	<- gets stateMap

	 	case Map.lookup v slotMap of
		 Nothing
		  -> do	ixSlot	<- newSlot
			let exp	= XVar (NSlot v ixSlot) t
			addSlotMap v exp

			return	$ SAssign exp tt x

		 Just exp
		  ->	return	$ SAssign exp tt x

	SAssign (XVar (NAuto v) _) t x
	 -> do	modify (\s -> s {
	 		stateAuto = (v, t) : stateAuto s })
		return ss

	_ 	-> return ss

