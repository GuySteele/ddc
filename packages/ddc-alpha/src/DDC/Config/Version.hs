{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | DDC id and version strings.
module DDC.Config.Version
	( ddcName
	, version
	, maintainers )
where


-- | The long name is added as a tag line to generated C files,
--	and used in the command line interface.
ddcName :: String
ddcName	= "The Disciplined Disciple Compiler, version " ++ version


-- | The version string.
version :: String
version	= "0.1.2"


-- | Maintainer contact string to put in panic messages.
maintainers :: String
maintainers
	=  "    http://disciple.ouroborus.net/\n"
	++ "    or by emailing disciple-cafe@googlegroups.com\n"
