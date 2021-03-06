module Llvm.Invoke
	( invokeLlvmCompiler
	, invokeLlvmAssembler )
where

import Main.Util

import Util
import System.Process
import System.Exit
import DDC.Main.Error

import qualified Config.Config			as Config

-----
stage	= "Llvm.Invoke"

-- | Invoke the external LLVM compiler to compile this LLVM Intermediate
--	Representation source program into native assembler.
invokeLlvmCompiler
	:: (?verbose :: Bool)
	=> FilePath		-- ^ path of source .ll file (must be canonical)
	-> FilePath             -- ^ path of output .s file  (must be canonical)
	-> [String]		-- ^ extra flags to compile with (from build files)
	-> IO ()

invokeLlvmCompiler
	pathLL
	pathS
	extraFlags
 = do
 	-- let cmd = Config.makeLlvmCompileCmd
	let cmd	= Config.llcCommand 
	        ++ " "    ++ pathLL
		++ " -o " ++ pathS

	outVerb $ ppr $ "\n"
		% "  * Invoking IR compiler.\n"
		% "    - command = \"" % cmd % "\"\n"

	retCompile	<- system cmd

	case retCompile of
	 ExitSuccess	-> return ()
	 ExitFailure _
	  -> panic stage
	  	$ "invokeLlvmCompiler: compilation of IR file failed.\n"
		% "    path = " % pathLL % "\n"



-- | Invoke the external assembler to compile this native assembler
--	source program into a native object file.
invokeLlvmAssembler
	:: (?verbose :: Bool)
	=> FilePath		-- ^ path of source .s file
	-> FilePath             -- ^ path of output .o file
	-> [String]		-- ^ extra flags to compile with (from build files)
	-> IO ()

invokeLlvmAssembler
	pathS
	pathO
	extraFlags
 = do
 	-- let cmd = Config.makeLlvmAssembleCmd
	let cmd	=  Config.asCommand 
	        ++ " "    ++ pathS
		++ " -o " ++ pathO

	outVerb $ ppr $ "\n"
		% "  * Invoking assembler.\n"
		% "    - command = \"" % cmd % "\"\n"

	retCompile	<- system cmd

	case retCompile of
	 ExitSuccess	-> return ()
	 ExitFailure _
	  -> panic stage
	  	$ "invokeLlvmAssembler: compilation of ASM file failed.\n"
		% "    path = " % pathS % "\n"

