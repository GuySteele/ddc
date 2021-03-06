{-# OPTIONS -fwarn-unused-imports #-}

-- | Wrappers for compiler stages dealing with Sea code.
module Main.Sea
	( compileViaSea
	, seaSub
	, seaCtor
	, seaThunking
	, seaForce
	, seaSlot
	, seaFlatten
	, seaInit
	, makeSeaHeader )
where
import Main.BuildFile
import Main.Dump
import Main.Util
import DDC.Main.Pretty
import DDC.Main.Setup
import DDC.Main.Result
import DDC.Sea.Exp
import DDC.Var
import Sea.Util
import Sea.Invoke
import Sea.Sub		(subTree)
import Sea.Ctor		(expandCtorTree)
import Sea.Proto	(addSuperProtosTree)
import Sea.Thunk	(thunkTree)
import Sea.Force	(forceTree)
import Sea.Slot		(slotTree)
import Sea.Flatten	(flattenTree)
import DDC.Sea.Init	(initTree, mainTree)
import Util
import Data.Char
import System.FilePath
import qualified DDC.Module.Scrape	as M
import qualified DDC.Main.Arg		as Arg
import qualified DDC.Core.Glob		as C
import qualified DDC.Config.Version	as Version
import qualified Sea.Util		as E
import qualified Data.Map		as Map


-- Sea stages used by all backends ----------------------------------------------------------------

-- | Substitute trivial x1 = x2 bindings
seaSub	:: (?args :: [Arg.Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()
	-> IO (Tree ())

seaSub tree
 = {-# SCC "Sea/sub" #-}
   do 	let tree' = subTree tree

	dumpET Arg.DumpSeaSub "sea-sub"
		$ eraseAnnotsTree tree'

	return tree'


-- | Expand code for data constructors.
seaCtor	:: (?args :: [Arg.Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()
	-> IO (Tree ())

seaCtor eTree
 = {-# SCC "Sea/ctor" #-}
   do	let eExpanded	= addSuperProtosTree
			$ expandCtorTree
			$ eTree

	dumpET Arg.DumpSeaCtor "sea-ctor"
		$ eraseAnnotsTree eExpanded

	return eExpanded


-- | Expand code for creating thunks
seaThunking
	:: (?args :: [Arg.Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()
	-> IO (Tree ())

seaThunking eTree
 = {-# SCC "Sea/thunking" #-}
   do	let tree'	= thunkTree eTree
	dumpET Arg.DumpSeaThunk "sea-thunk"
		$ eraseAnnotsTree tree'

	return tree'


-- | Add code for forcing suspensions
seaForce
	:: (?args :: [Arg.Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()
	-> IO (Tree ())

seaForce eTree
 = {-# SCC "Sea/force" #-}
   do	let tree'	= forceTree eTree
	dumpET Arg.DumpSeaForce "sea-force"
		$ eraseAnnotsTree tree'

 	return	tree'


-- | Store pointers on GC slot stack.
seaSlot
	:: (?args :: [Arg.Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()		-- sea tree
	-> Tree ()		-- sea header
	-> C.Glob		-- header glob, used to get arities of supers
	-> C.Glob		-- source glob, TODO: refactor to take from Sea glob
	-> IO (Tree ())

seaSlot	eTree eHeader cgHeader cgSource
 = {-# SCC "Sea/slot" #-}
   do	let tree'	= slotTree eTree eHeader cgHeader cgSource
	dumpET Arg.DumpSeaSlot "sea-slot"
		$ eraseAnnotsTree tree'

	return	tree'


-- | Flatten out match expressions.
seaFlatten
	:: (?args :: [Arg.Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> String
	-> Tree ()
	-> IO (Tree ())

seaFlatten unique eTree
 = {-# SCC "Sea/flatten" #-}
   do	let tree'	= flattenTree unique eTree
	dumpET Arg.DumpSeaFlatten "sea-flatten"
		$ eraseAnnotsTree tree'

	return	tree'


-- | Add module initialisation code
seaInit	:: (?args :: [Arg.Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> ModuleId
	-> (Tree ())
	-> IO (Tree ())

seaInit moduleName eTree
 = {-# SCC "Sea/init" #-}
   do 	let tree'	= initTree moduleName eTree
 	dumpET Arg.DumpSeaInit "sea-init"
		$ eraseAnnotsTree tree'

	return tree'


-- | Create the C header file for this module.
makeSeaHeader :: ModuleId -> (Tree ()) -> String -> [String] -> [String] -> String
makeSeaHeader modName eTree pathThis pathImports extraIncludes
 = do		-- Break up the sea into Header/Code parts.
	let 	([ seaProtos, seaCafProtos, seaCtorTag, seaCtorStructs ], _junk)
		 = partitionBy
			[ (=@=) PProto{}, (=@=) PCafProto{}, (=@=) PCtorTag{}, (=@=) PCtorStruct{} ]
			eTree

	let defTag	= makeIncludeDefTag pathThis

	pprStrPlain
	 $ vcat	[ "#ifndef _inc" % defTag
		, "#define _inc" % defTag
		, blank
		, ppr "#include <runtime/Runtime.h>"
		, ppr "#include <runtime/Runtime.ci>"
		, blank
		, vcat [ "#include <" % inc % ">" | inc <- pathImports ]
		, vcat [ "#include <" % inc % ">" | inc <- extraIncludes]
		, blank, vcat $ eraseAnnotsTree seaCtorTag
		, blank, vcat $ eraseAnnotsTree
						$ filter (isModuleLocal modName) seaCtorStructs
		, blank, vcat $ eraseAnnotsTree seaCafProtos
		, blank, vcat $ eraseAnnotsTree seaProtos
		, blank, ppr "#endif"
		, blank ]

isModuleLocal :: ModuleId -> Top () -> Bool
isModuleLocal modName (PCtorStruct v _)
 = modName == varModuleId v


nameTItoH nameTI
 = let	parts	= chopOnRight '.' nameTI
   in   concat (init parts ++ ["ddc.h"])

makeIncludeDefTag pathThis
 = filter (\c -> isAlpha c || isDigit c)
 	$ pathThis


---------------------------------------------------------------------------------------------------
-- Sea stages specific to the -fvia-c backend.

-- | Compile a Sea module via the C compiler.
compileViaSea
	:: Setup			-- ^ Compile setup.
	-> ModuleId			-- ^ Module to compile, must also be in the scrape graph.
	-> Tree ()			-- ^ The Sea Tree for the module.
	-> FilePath			-- ^ path of source .ds file.
	-> FilePath			-- ^ path of created .di file.
	-> [FilePath]			-- ^ C import directories.
	-> [FilePath]			-- ^ C include files.
	-> Map ModuleId [a]		-- ^ Module import map.
	-> Bool				-- ^ Module defines 'main' function.
	-> M.Scrape			-- ^ Scrape graph of this module.
	-> Map ModuleId M.Scrape	-- ^ Scrape graph of all modules reachable from the root.
	-> Bool				-- ^ Whether to treat a 'main' function defined by this module
					--	as the program entry point.
	-> IO Result

compileViaSea
	setup modName eInit
	pathDS pathDI
	importDirs includeFilesHere
	importsExp
	modDefinesMainFn
	sRoot scrapes_noRoot
	blessMain
 = {-# SCC "Sea/compile" #-}
    do	let ?args		= setupArgs setup
        let ?verbose            = elem Arg.Verbose (setupArgs setup)

	-- Generate C source code ---------------------------------------------
	outVerb $ ppr $ "  * Generate C source code\n"
	(  seaHeader
	 , seaSource )	<- outSea setup modName eInit pathDS
				(map ((\(Just f) -> f) . M.scrapePathHeader)
					$ Map.elems scrapes_noRoot)
				includeFilesHere


	-- If this module binds the top level main function
	--	then append RTS initialisation code.
	seaSourceInit
	 <- if modDefinesMainFn && blessMain
	     then do
		let mainCode = mainTree
				modName
				(map fst $ Map.toList importsExp)
				(not     $ elem Arg.NoImplicitHandler ?args)
				(join    $ liftM buildStartHeapSize         $ M.scrapeBuild sRoot)
				(join    $ liftM buildStartSlotStackSize    $ M.scrapeBuild sRoot)
				(join    $ liftM buildStartContextStackSize $ M.scrapeBuild sRoot)

		return 	$ seaSource
			++ (catInt "\n" $ map pprStrPlain $ E.eraseAnnotsTree mainCode)

	     else return seaSource

	-- Write C files ------------------------------------------------------
	outVerb $ ppr $ "  * Write C files\n"
	let baseDS	= takeBaseName pathDS
	let dirDS	= takeDirectory pathDS
	let outputDir	= fromMaybe dirDS (outputDirOfSetup setup)
	let pathC	= outputDir </> addExtension baseDS ".ddc.c"
	let pathH	= outputDir </> addExtension baseDS ".ddc.h"
	let pathO	= outputDir </> addExtension baseDS ".o"

	writeFile pathC seaSourceInit
	writeFile pathH seaHeader

	-- Invoke external compiler / linker ----------------------------------
	-- !! Early exit on StopSea
	when (elem Arg.StopSea ?args)
		compileExit

	-- Invoke GCC to compile C source.
	invokeSeaCompiler
		?args
		pathC
		pathO
		(setupRuntime setup)
		(setupLibrary setup)
		importDirs
		(fromMaybe [] $ liftM buildExtraCCFlags (M.scrapeBuild sRoot))

	return	$ Result
		{ resultModuleId	= modName
		, resultDefinesMain	= modDefinesMainFn
		, resultSourceDS	= pathDS
		, resultOutputDI	= pathDI
		, resultOutputC		= Just pathC
		, resultOutputH		= Just pathH
		, resultOutputO		= Just pathO
		, resultOutputExe	= Nothing }


-- | Create C source files
outSea	:: Setup                -- compilation setup
	-> ModuleId             -- id of the module being compiled
	-> (Tree ())		-- sea source
	-> FilePath		-- path of the source file
	-> [FilePath]		-- paths of the imported .h header files
	-> [String]		-- extra header files to include
	-> IO	( String
		, String )

outSea setup moduleName eTree pathThis pathImports extraIncludes
 = {-# SCC "Sea/out" #-}
	-- Break up the sea into Header/Code parts.
    let	([ 	_seaProtos, 		seaSupers,		_seaExterns
	 , 	_seaCafProtos,		seaCafSlots,		seaCafInits
	 ,      seaData,		_seaCtorStructs
	 , 	_seaPCtorTag ], [])

	 = partitionBy
		[ (=@=) PProto{}, 	(=@=) PSuper{}, 	(=@=) PExtern{}
		, (=@=) PCafProto{},	(=@=) PCafSlot{},	(=@=) PCafInit{}
		, (=@=) PData{},	(=@=) PCtorStruct{}
		, (=@=) PCtorTag{} ]
		eTree

 	-- Build the C header
	seaHeader = makeSeaHeader moduleName eTree pathThis pathImports extraIncludes

	-- Build the C code.
	seaCode	= pprStrPlain $ vcat
		[ ppr   "// -----------------------"
		, ppr $ "//       source: " % pathThis
		, ppr $ "// generated by: " % Version.ddcName
		, blank

		-- include own .h file.
		, let Just name	= takeLast $ chopOnRight '/' $ nameTItoH pathThis
		  in  "#include" %% dquotes name

		, blank, vcat $ eraseAnnotsTree seaData

		, blank, vcat $ eraseAnnotsTree seaCafSlots
		, blank, vcat $ eraseAnnotsTree seaCafInits
		, blank, vcat $ eraseAnnotsTree seaSupers ]

   in return	( seaHeader
		, seaCode )

