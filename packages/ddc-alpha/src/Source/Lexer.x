
{
{-# OPTIONS_GHC -Wwarn #-}
{-# OPTIONS
	-fno-warn-monomorphism-restriction
	-fno-warn-unused-binds
	-fno-warn-incomplete-record-updates
	-O2 #-}

module Source.Lexer
	( dropStrComments
	, dropTokComments
	, scan
	, scanModuleWithOffside
	, showSource
	, sourceTokens
	, alexScanTokens)

where
import Source.Token
import Source.TokenShow
import DDC.Source.Error
import DDC.Base.DataFormat
import DDC.Base.Literal
import DDC.Main.Error
import Data.Char	(isUpper)
import Util
}

%wrapper "posn"

$digit		= [0-9]
$hexdigit	= [0-9a-f]
$octdigit	= [0-7]
$bindigit	= [0-1]

$upper	= [A-Z]
$lower  = [a-z]
$alpha	= [$lower $upper]

-- The symbols that can appear in a var
$varsym	= [\' \_]

$sym		= [\. \! \# \$ \% \& \* \+ \/ \< \> \? \@ \^ \- \~ \\ \= \: \|]
$var		= [$alpha $digit $varsym]

@escDoubleQuote	= (\\ \")


@moduleSpec	= ($upper [$alpha $digit]* \.)*
@nameSpaceQual	= [\* \% \! \$]?

tokens :-
 $white # \n		;

 \n			{ ptag NewLine			}

-- Comment pragma before comment block comments.
 \{ \- \# .* \# \- \}	{ ptags CommentPragma		}

 \{ \-			{ ptag CommentBlockStart	}
 \- \}			{ ptag CommentBlockEnd		}

-- Need this so so that things like '#-}' and '+-}' are correctly detected as CommentBlockEnd tokens.
 $sym \- \}		{ ptag CommentBlockEnd		}

 \- \- \-*		{ ptag CommentLineStart		}

 pragma			{ ptag Pragma			}

 foreign		{ ptag Foreign			}
 import			{ ptag Import			}
 export			{ ptag Export			}

 module			{ ptag Module			}
 elaborate		{ ptag Elaborate		}
 const			{ ptag Const			}
 mutable		{ ptag Mutable			}
 extern			{ ptag Extern			}
 ccall			{ ptag CCall			}

 infixr 		{ ptag InfixR			}
 infixl			{ ptag InfixL			}
 infix			{ ptag Infix			}

 type			{ ptag Type			}
 data			{ ptag Data			}
 effect			{ ptag Effect			}
 region			{ ptag Region			}

 class			{ ptag Class			}
 instance		{ ptag Instance			}
 project		{ ptag Project			}

 let			{ ptag Let			}
 in			{ ptag In			}
 where			{ ptag Where			}

 case			{ ptag Case 			}
 of			{ ptag Of			}
 match			{ ptag Match			}

 if			{ ptag If			}
 then			{ ptag Then			}
 else			{ ptag Else			}

 do			{ ptag Do			}
 while			{ ptag While			}
 when			{ ptag When			}
 unless			{ ptag Unless			}
 break			{ ptag Break			}

 throw			{ ptag Throw			}
 try			{ ptag Try			}
 catch			{ ptag Catch			}
 with			{ ptag With			}

 forall			{ ptag Forall			}

 true\#			{ ptag (mkLit (LBool True)  Unboxed) }
 false\#		{ ptag (mkLit (LBool False) Unboxed) }

 __FILE__		{ ptag CLFile			}
 __FUNC__		{ ptag CLFunc			}
 __LINE__		{ ptag CLLine			}
 __MODULE__		{ ptag CLModule			}

 \:\:			{ ptag HasTypeMatch		}
 \=\:			{ ptag HasTypeExact		}
 \<\:			{ ptag HasTypeLess		}
 \:\>			{ ptag HasTypeMore		}

 \:\$			{ ptag HasOpType		}
 \:\-			{ ptag HasConstraint		}

 \-\>			{ ptag RightArrow		}
 \=\>			{ ptag RightArrowEquals		}
 \$\>			{ ptag HoldsMono		}

 \(\)			{ ptag Unit			}
 \.\.			{ ptag DotDot			}

 \<\-			{ ptag LeftArrow		}
 \<\@\-			{ ptag LeftArrowLazy		}

 \| \-			{ ptag GuardCase		}
 \, \|			{ ptag GuardCaseC		}

 \| \#			{ ptag GuardUnboxed		}
 \, \#			{ ptag GuardUnboxedC		}
 \\ \=			{ ptag GuardDefault		}
 \\ \.			{ ptag BackSlashDot		}

 $sym $sym+		{ ptags (\s -> Symbol s)	}

 \#			{ ptag Hash			}
 \*			{ ptag Star			}
 \+			{ ptag Plus			}
 \%			{ ptag Percent			}
 \-			{ ptag Dash			}
 \@			{ ptag At			}
 \!			{ ptag Bang			}
 \/			{ ptag ForwardSlash		}
 \$			{ ptag Dollar			}
 \_			{ ptag Underscore		}
 \^			{ ptag Hat			}
 \~			{ ptag Tilde			}

 \<			{ ptag ABra			}
 \>			{ ptag AKet			}

 \{			{ ptag CBra			}
 \}			{ ptag CKet			}

 \(			{ ptag RBra			}
 \)			{ ptag RKet			}

 \[			{ ptag SBra			}
 \]			{ ptag SKet			}

 \\			{ ptag BackSlash		}
 \`			{ ptag BackTick			}
 \=			{ ptag Equals			}
 \,			{ ptag Comma			}
 \:			{ ptag Colon			}
 \;			{ ptag SemiColon		}
 \|			{ ptag Bar			}
 \.			{ ptag Dot			}
 \&			{ ptag And			}

 @moduleSpec @nameSpaceQual $lower $var*
 			{ ptags (\s -> Var   s) 	}

 @moduleSpec @nameSpaceQual $upper $var* \#?
 			{ ptags (\s -> Con   s) 	}

 \_ $var*		{ ptags (\s -> case s of (x:xs) -> VarField xs)	}

 $sym+  $sym*		{ ptags (\s -> Symbol s)	}



 \" (@escDoubleQuote | (. # \"))* \"\#	{ ptags (\s -> mkLit (LString $ (drop 1 $ dropLast 2 s)) Unboxed) }
 \" (@escDoubleQuote | (. # \"))* \" 	{ ptags (\s -> mkLit (LString $ (drop 1 $ dropLast 1 s)) Boxed) }

 0b $bindigit+ \# i $digit*		{ ptags (\s -> makeLiteralUB 'i' LInt s) }
 0b $bindigit+ \# u $digit*		{ ptags (\s -> makeLiteralUB 'u' LWord s) }
 0b $bindigit+ i $digit* \# 		{ ptags (\s -> makeLiteralUB 'i' LInt s) }
 0b $bindigit+ u $digit* \# 		{ ptags (\s -> makeLiteralUB 'u' LWord s) }

 0b $bindigit+ \# 			{ ptags (\s -> mkLit (LInt $ readBinWrap $ dropLast 1 s) Unboxed) }

 0b $bindigit+ i $digit*		{ ptags (\s -> makeLiteralB 'i' LInt s) }
 0b $bindigit+ u $digit*		{ ptags (\s -> makeLiteralB 'u' LWord s) }
 0b $bindigit+				{ ptags (\s -> mkLit (LInt $ readBinWrap s) Boxed) }

 0o $octdigit+ \# i $digit*		{ ptags (\s -> makeLiteralUB 'i' LInt s) }
 0o $octdigit+ \# u $digit*		{ ptags (\s -> makeLiteralUB 'u' LWord s) }
 0o $octdigit+ i $digit* \#		{ ptags (\s -> makeLiteralUB 'i' LInt s) }
 0o $octdigit+ u $digit* \#		{ ptags (\s -> makeLiteralUB 'u' LWord s) }
 0o $octdigit+ \# 			{ ptags (\s -> mkLit (LInt $ read $ dropLast 1 s) Unboxed) }

 0o $octdigit+ i $digit*		{ ptags (\s -> makeLiteralB 'i' LInt s) }
 0o $octdigit+ u $digit*		{ ptags (\s -> makeLiteralB 'u' LWord s) }
 0o $octdigit+				{ ptags (\s -> mkLit (LInt $ read s) Boxed) }

 0x $hexdigit+ \# i $digit*		{ ptags (\s -> makeLiteralUB 'i' LInt s) }
 0x $hexdigit+ \# u $digit*		{ ptags (\s -> makeLiteralUB 'u' LWord s) }
 0x $hexdigit+ i $digit* \#		{ ptags (\s -> makeLiteralUB 'i' LInt s) }
 0x $hexdigit+ u $digit* \#		{ ptags (\s -> makeLiteralUB 'u' LWord s) }
 0x $hexdigit+ \# 			{ ptags (\s -> mkLit (LInt $ read $ dropLast 1 s) Unboxed) }

 0x $hexdigit+ i $digit*		{ ptags (\s -> makeLiteralB 'i' LInt s) }
 0x $hexdigit+ u $digit*		{ ptags (\s -> makeLiteralB 'u' LWord s) }
 0x $hexdigit+				{ ptags (\s -> mkLit (LInt $ read s) Boxed) }

 $digit+ \. $digit+ \# f $digit*	{ ptags (\s -> makeLiteralUB 'f' LFloat s) }
 $digit+ \. $digit+ \# 			{ ptags (\s -> mkLit (LFloat $ read $ dropLast 1 s) Unboxed) }
 $digit+ \. $digit+    f $digit*	{ ptags (\s -> makeLiteralB  'f' LFloat s) }
 $digit+ \. $digit+			{ ptags (\s -> mkLit (LFloat $ read s) Boxed) }

 $digit+ \# u $digit*			{ ptags (\s -> makeLiteralUB 'u' LWord s) }
 $digit+ u $digit* \#			{ ptags (\s -> makeLiteralUB 'u' LWord s) }
 $digit+    u $digit*			{ ptags (\s -> makeLiteralB  'u' LWord s) }

 $digit+ \# i $digit*			{ ptags (\s -> makeLiteralUB 'i' LInt s) }
 $digit+ i $digit* \#			{ ptags (\s -> makeLiteralUB 'i' LInt s) }
 $digit+ \# 				{ ptags (\s -> mkLit (LInt $ read $ dropLast 1 s) Unboxed) }
 $digit+    i $digit*			{ ptags (\s -> makeLiteralB  'i' LInt s) }
 $digit+				{ ptags (\s -> mkLit (LInt $ read s) Boxed) }

 \'\\n\' \#				{ ptags (\s -> mkLit (LChar $ read $ dropLast 1 s) (UnboxedBits 32)) }
 \' . \' \#				{ ptags (\s -> mkLit (LChar $ read $ dropLast 1 s) (UnboxedBits 32)) }

 \'\\n\'				{ ptags (\s -> mkLit (LChar $ read s) (BoxedBits 32)) }
 \' . \'				{ ptags (\s -> mkLit (LChar $ read s) (BoxedBits 32)) }

 .					{ ptags (\s -> Junk s)			}


{

----------------------------------------------------------------------------------------------------

stage	= "Source.Lexer"


-- | Drop the last n characters from a string
dropLast :: Int -> String -> String
dropLast n str
	= take (length str - n) str

-- | Rag a generated token with its position
ptags :: (String -> Token) -> AlexPosn -> String -> TokenP
ptags 	  tokf (AlexPn _ l c)	s
 = TokenP
 	{ token		= (tokf s)
	, tokenFile	= "unknown"
	, tokenLine 	= l
	, tokenColumn 	= c }

-- | Tag a token with its position
ptag ::  Token -> AlexPosn -> String -> TokenP
ptag	 tok (AlexPn _ l c) s
 = TokenP
 	{ token		= tok
	, tokenFile	= "unknown"
	, tokenLine	= l
	, tokenColumn	= c }

-- makeLiteral -------------------------------------------------------------------------------------
makeLiteralUB :: (Num a, Read a) => Char -> (a -> Literal) -> String -> Token
makeLiteralUB spec con ss
	| (num, '#':spec':bits)	<- splitOnLeft '#' ss
	, spec == spec'
	= case bits of
 	   []	-> mkLit (con $ readBinWrap num) Unboxed
	   _	-> mkLit (con $ readBinWrap num) (UnboxedBits $ read bits)

	| (num, spec':bits) <- splitOnLeft spec ss
	, spec == spec'
	= case bits of
 	   []	-> mkLit (con $ readBinWrap num) Unboxed
	   _	-> mkLit (con $ readBinWrap num)
				(UnboxedBits $ read
				$ if last bits == '#' then init bits else bits)

makeLiteralB :: (Num a, Read a) => Char -> (a -> Literal) -> String -> Token
makeLiteralB spec con ss
 	| (num, spec':bits)	<- splitOnLeft spec ss
	, spec == spec'
	= case bits of
	   []	-> mkLit (con $ readBinWrap num) Boxed
	   _	-> mkLit (con $ readBinWrap num) (BoxedBits $ read bits)

mkLit :: Literal -> DataFormat -> Token
mkLit lit fmt	= Literal $ LiteralFmt lit fmt

readBinWrap :: (Num a, Read a) => String -> a
readBinWrap ('0' : 'b' : rest)
 = foldl' (\ acc b -> if b then 2 * acc + 1 else 2 * acc) 0
	$ map (/= '0') rest

readBinWrap num = read num

-- scan --------------------------------------------------------------------------------------------
-- This is the top level of the scanner
-- Add a newline to help ourselves out

scanModuleWithOffside
	:: String
	-> ( [TokenP]		-- source tokens
	   , [TokenP] )		-- pragma tokens

scanModuleWithOffside str
 = let	toks		= scan str

	(toksPragma, toksSource)
		= partition isTokPragma toks

	toksSourceOffside
		= (flip offside) [] 		-- apply the offside rule
		$ addStarts toksSource 0	-- add BlockStart / LineStart tokens in preparation for offside rule

  in	( toksSourceOffside
	, toksPragma)

scan :: String -> [TokenP]
scan ss
	= breakModules 		-- detect module names, and break into projections if required
	$ dropTokComments 	-- remove comments
	$ alexScanTokens ss

sourceTokens ts
	= catInt " " $ map showSourceP ts

isTokPragma tok
 = case tok of
	TokenP { token = CommentPragma _ }	-> True
	_					-> False

lexOffside :: String -> String
lexOffside ss = sourceTokens $ scan ss

-- dropTokComments -------------------------------------------------------------------------------------
-- | Drop all the comments in this token stream
dropTokComments ::	[TokenP] -> [TokenP]
dropTokComments 	[]	= []
dropTokComments	(t@TokenP { token = tok } : xs)
	| CommentLineStart	<- tok
	= dropTokComments $ dropWhile (\t -> not $ isToken t NewLine) xs

	| CommentBlockStart	<- tok
	= dropTokComments $ dropTokCommentBlock xs t

	| otherwise
	= t : dropTokComments xs

dropTokCommentBlock :: [TokenP] -> TokenP -> [TokenP]
dropTokCommentBlock	[]	terror = dieWithUserError [ErrorUnterminatedCommentBlock terror]
dropTokCommentBlock	(t@TokenP { token = tok } : xs) terror
	| CommentBlockStart	<- tok
	= dropTokCommentBlock (dropTokCommentBlock xs t) terror

	| CommentBlockEnd	<- tok
	= xs

	| otherwise
	= dropTokCommentBlock xs terror


-- dropStrComments --------------------------------------------------------------------------------
-- | When parsing the module import list when doing a recursive build
--	we want to drop comments in the source file directly.
--	This makes the file easier to parse, but we also loose token position information,
--	so we don't use it when parsing the file proper.
--
dropStrComments :: String -> String
dropStrComments xx
 = case xx of
	[]		-> []
	('-':'-':xs)	-> dropStrComments $ dropWhile (/= '\n') xs
	('{':'-':xs)	-> dropStrComments $ dropStrCommentBlock xs
	(x:xs)		-> x : dropStrComments xs

dropStrCommentBlock :: String -> String
dropStrCommentBlock xx
 = case xx of
	[]		-> []
	('{':'-':xs)	-> dropStrCommentBlock $ dropStrCommentBlock xs
	('-':'}':xs)	-> xs
	(x:xs)		-> dropStrCommentBlock xs


-- breakModules ------------------------------------------------------------------------------------
-- | Break module qualifiers off var and con tokens
breakModules :: [TokenP] -> [TokenP]
breakModules toks
	= catMap breakModules' toks

breakModules' tok@(TokenP { token = tt })
	| Var str	<- tt
	, (mods, name)	<- breakModuleStr str
	= case mods of
	   [] 	-> [tok]
	   _	-> [ tok { token = ModuleName mods}
		   , tok { token = Dot }
		   , tok { token = Var name } ]

	| Con str	<- tt
	, (mods, name)	<- breakModuleStr str
	= case mods of
	   [] 	-> [tok]
	   _	-> [ tok { token = ModuleName mods}
		   , tok { token = Dot }
		   , tok { token = Con name} ]
breakModules' t
	= [t]


-- Break module qualifiers off this variable name
breakModuleStr
	:: String		-- ^ variable name
	-> ([String], String)	--   qualifiers and base name

breakModuleStr str
	| bits		<- breakOns '.' str

	-- at least one qualifier
 	, length bits > 1

	-- lexer sanity
	--	not more than one consecutive dot.
	, minimum (map length bits) > 0

	-- peel of the front bits that look like module qualifiers
	, Just front	<- takeInit bits
	, Just back	<- takeLast bits
	, moduleBits	<- takeWhile (\b -> let Just h = takeHead b in isUpper h) front

	-- lexer sanity
	--	only one variable name
	--	ie not   Module.var1.var2
	, length bits == length moduleBits + 1
	= (moduleBits, back)

	| otherwise
	= ([], str)


-- addStarts ---------------------------------------------------------------------------------------
-- | Add block and line start tokens to this stream.
--	This is lifted straight from the Haskell98 report.
addStarts :: [TokenP] -> Int -> [TokenP]
addStarts ts listNestCount
 = case forward ts of

	-- if the first lexeme of a module is not '{' then start a new block
 	(t1 : tsRest)
	  |  not $ or $ map (isToken t1) [CBra]
	  -> StartBlock (tokenColumn t1) : addStarts' (t1 : tsRest) listNestCount

	  | otherwise
	  -> addStarts' (t1 : tsRest) listNestCount

	-- empty file
	[]	-> []


addStarts'  :: [TokenP] -> Int -> [TokenP]
addStarts' [] _	= []

addStarts'
	( t1@TokenP { token = Foreign }
	: t2@TokenP { token = Import }
	: ts) listNestCount
	= t1 : t2 : addStarts' ts listNestCount

addStarts' (t1 : ts) listNestCount

	-- We're starting a block
	| isBlockStart t1 listNestCount
	, []		<- forward ts
	= t1 : [StartBlock 0]

	| isBlockStart t1 listNestCount
	, t2 : tsRest	<- forward ts
	, not $ isToken t2 CBra
	= t1	: StartBlock (tokenColumn t2)
		: addStarts' (t2 : tsRest) listNestCount

	-- check for start of list
	| isToken t1 SBra
	= t1 : addStarts' ts (listNestCount + 1)

	-- check for end of list
	| isToken t1 SKet
	= t1 : addStarts' ts (listNestCount - 1)

	-- check for start of new line
	| isToken t1 NewLine
	, t2 : tsRest	<- forward ts
	, not $ isToken t2 CBra
	= StartLine (tokenColumn t2) : addStarts' (t2 : tsRest) listNestCount

	-- eat up trailine newlines
	| isToken t1 NewLine
	= addStarts' ts listNestCount

	-- a regular token
	| otherwise
	= t1 : addStarts' ts listNestCount

isToken :: TokenP -> Token -> Bool
isToken TokenP { token = tok } t2	= tok == t2
isToken _ _				= False

-- check if a token is one that starts a block of statements.
isBlockStart :: TokenP -> Int -> Bool
isBlockStart TokenP { token = tok } listNestCount
 = case tok of
 	Do		-> True
	Of		-> True
	Where		-> True
	With		-> True
	Let		-> listNestCount < 1
	Catch		-> True
	Match		-> True
	Import		-> True
	Export		-> True
	_		-> False

isBlockStart _ _
	= False

-- scan forward through the stream to get to the next non-newline token
forward :: [TokenP] 	-> [TokenP]
forward []		= []
forward (t1:ts)
	| TokenP { token = tok }	<- t1
	, NewLine			<- tok
	= forward ts

	| otherwise
	= t1 : ts



-- offside -----------------------------------------------------------------------------------------
-- | Apply the offside rule to this token stream.
--	They should have been processed with addStarts first to add the StartBlock/StartLine tokens.
--	This is lifted straight from the Haskell98 report.
--
type Context	= Int

offside	:: [TokenP] -> [Context] -> [TokenP]

offside ts ms
 = {- trace (
  	 "offside: \n"
 	 ++ "   ts = " ++ show ts ++ "\n"
	 ++ "   ms = " ++ show ms ++ "\n") $ -}
	offside' ts ms

-- avoid starting a new statement if the first token on the line is an '=', ',' or '->'
-- 	This allows the syntax of match and case expressions to line up nicely
-- eg
--	match 	| guard1
--		, guard2
--		= exp1
--
--		| guard2
--		= exp2
offside' (t1@(StartLine n) : t2 : ts) (m : ms)
	| isToken t2 Equals || isToken t2 Comma || isToken t2 RightArrow
	= offside (t2 : ts) (m : ms)

-- line start
offside' (t@(StartLine n) : ts) (m : ms)

	-- add semicolon to get to the next statement in this block
	| m == n	= newSemiColon ts : offside ts (m : ms)

	-- end a block
	-- we keep the StartLine token in the recursion in case we're ending multiple blocks
	-- difference from Haskell98: add a semicolon as well

	| n < m		= newSemiColon ts : newCKet ts : offside (t : ts) ms

	-- indented continuation of this statement
	| otherwise
	= offside ts (m : ms)

-- block start
offside' (t@(StartBlock n) : ts) mm

	-- enter into a nested context
	| m : ms	<- mm
	, n > m
	= newCBra ts : offside ts (n : m : ms)

	-- enter into an initial context (at top level)
	| []		<- mm
	, n > 0
	= newCBra ts : offside ts (n : [])


	-- new context cannot be less indented than outer one
	-- This case should never happen.
	--	There is no lexeme to start a new context at the end of the file
	| []		<- forward ts
	= panic stage
	$ "offside: Tried to open a new context at the end of the file."

	-- new context starts less than the current one
	| tNext : _	<- forward ts
	= dieWithUserError [ErrorLayoutLeft tNext]

	-- an empty block
	| otherwise
	= newCBra ts : newCKet ts : offside (StartLine n : ts) mm


-- pop contexts from explicit close braces
offside' (t@TokenP { token = CKet } : ts) mm

	-- make sure that explict open braces match explicit close braces
	| 0 : ms	<- mm
	= t : offside ts ms

	-- nup
	| tNext : _	<- forward ts
	= dieWithUserError [ErrorLayoutNoBraceMatch tNext]

-- push contexts for explicit open braces
offside' (t@TokenP { token = CBra } : ts) ms

	= t : offside ts (0 : ms)

-- i'm totally ignoring the rule that inserts
--	close braces on parse errors -- that's crazy talk.

offside' (t : ts) ms	= t : offside ts ms

offside' [] []		= []

-- close off remaining contexts once we've reached the end of the stream.
offside' [] (m : ms)	= newCKet [] : offside [] ms


-- When generating new source tokens, take the position from the first non-newline token in this list
newCBra :: [TokenP] -> TokenP
newCBra ts	= (takeTok ts) { token = CBra }

newCKet :: [TokenP] -> TokenP
newCKet	ts	= (takeTok ts) { token = CKet }

newSemiColon :: [TokenP] -> TokenP
newSemiColon ts = (takeTok ts) 	{ token = SemiColon }

takeTok :: [TokenP] -> TokenP
takeTok tt
 = case forward tt of
 	[]	-> TokenP { token = Junk "", tokenFile = [], tokenLine = 0, tokenColumn = 0}
	(t:_)	-> t



}




