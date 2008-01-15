GHC=ghc

# -- Optimised / distribution compile
# GHC_FLAGS	:= -fglasgow-exts -tmpdir /tmp -O2 
# GCC_FLAGS	:= -std=c99 -Werror -Wundef -fPIC

# -- Profiling compile
# GHC_FLAGS	:= -fglasgow-exts -tmpdir /tmp -O2 -prof -auto-all
# GCC_FLAGS	:= -std=c99 -Werror -Wundef -g -pg -fPIC

# -- Development compile
GHC_FLAGS	:= -XPatternGuards -XImplicitParams -XUnboxedTuples -XParallelListComp -XPatternSignatures \
		   -XMultiParamTypeClasses -XFlexibleInstances -XFlexibleContexts -XFunctionalDependencies \
		   -tmpdir /tmp -Onot
GCC_FLAGS	:= -std=c99 -Wundef -fPIC

# -- For Haskell Program Coverage
# GHC_FLAGS	:= -fhpc -fallow-undecidable-instances -fglasgow-exts -tmpdir /tmp 
# GCC_FLAGS	:= -std=c99 -Wundef -fPIC -O3
