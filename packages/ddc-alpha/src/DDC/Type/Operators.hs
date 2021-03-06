
-- | Type operators that map types to types.
module DDC.Type.Operators
	( 
	-- * Beautification of variable names
	  beautifyNamesT
	, beautifyLocalNamesT

	-- * Discharging constraints	
	, reduceContextT

	-- * Crushing
	, crushT, crushK

	-- * Cutting loops
	, cutLoopsT

	-- * Dragging
	, dragT

	-- * Elaboration
	, elaborateRsT
	, elaborateEffT
	, elaborateCloT
		
	-- * Finalisation
	, finaliseT
	
	-- * Fixup kind annotations
	, fixupKindsT
	
	-- * Flattening
	, flattenT
	
	-- * Instantiation
	, instantiateT
	, instantiateWithFreshVarsT
	
	-- * Joining
	, joinSumTs
	
	-- * Masking effects
	, maskLocalT
	
	-- * Packing
	, packT
	, packAndMarkLoopsT
	
	-- * Quantification
	, quantifyVarsT
	
	-- * Stripping
	, stripFWheresT
	, stripMonoFWheresT
	, stripForallContextT
	, stripToBodyT
	
	-- * Substitution
	, subTT_noLoops
	, subTTK_noLoops
	, subTT_everywhere
	, subVT_everywhere
	, subVV_everywhere
	, subCidCid_everywhere
	, subHashVT_noLoops
	
	-- * Trimming closures
 	, trimClosureT
	, trimClosureNoDangerT
	, trimClosureC
	, trimClosureNoDangerC)
where
import DDC.Type.Operators.Beautify
import DDC.Type.Operators.Context
import DDC.Type.Operators.Crush
import DDC.Type.Operators.CutLoops
import DDC.Type.Operators.Drag
import DDC.Type.Operators.Elaborate
import DDC.Type.Operators.Finalise
import DDC.Type.Operators.Fixup
import DDC.Type.Operators.Flatten
import DDC.Type.Operators.Instantiate
import DDC.Type.Operators.JoinSum
import DDC.Type.Operators.MaskLocal
import DDC.Type.Operators.Pack
import DDC.Type.Operators.Quantify
import DDC.Type.Operators.Strip
import DDC.Type.Operators.Substitute
import DDC.Type.Operators.SubHash
import DDC.Type.Operators.Trim
