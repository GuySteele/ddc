-- Error handling.
--	Provides functions for emitting panics, freakouts and warnings.
--
module Shared.Error
	( panic
	, freakout
	, warning
	, dieWithUserError)
where

-----
import Util
import Util.PrettyPrint
import Debug.Trace


-- | The walls are crashing down.
--	Print a last, dying message and bail out.
--
panic :: Pretty msg => String -> msg -> a
panic  stage msg
	=  error
		( pretty $ "PANIC in " % stage % "\n" 
		%> (msg % "\n\nPlease report this as a bug to the maintainers.\n"))


-- | Something bad has happened, and it's likely to be terminal.
--	Hopefully we can contine on for a bit longer until some other error occurs
--	that gives information about what caused this problem.
--
freakout :: Pretty msg => String -> msg -> a -> a
freakout stage msg a
	= trace 
		(pretty $ "FREAKOUT in " % stage % "\n"
		%> (msg	% "\n\nPlease report this as a bug to the maintainers.\n"))
		a

	
-- | Something troubling has happened, but it's not likely to be terminal.
--	We'll print the message to the console to let the user know that something's up.
--
warning :: Pretty msg => String -> msg -> a -> a
warning stage msg a
	= trace (pretty $ "WARNING in " % stage % "\n" %> msg) 
		a


-- | A regular compile time error in the user program.
--	Report the errors and bail out.
--
dieWithUserError :: Pretty err => [err] -> a
dieWithUserError  errs
	= error	(pretty $ "ERROR\n\n" ++ (catInt "\n" $ map pretty errs))

	
