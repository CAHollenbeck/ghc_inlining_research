%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1996
%
\section[PrelMods]{Definitions of prelude modules}

The strings identify built-in prelude modules.  They are
defined here so as to avod
\begin{code}
#include "HsVersions.h"

module PrelMods (
	pRELUDE, pRELUDE_BUILTIN, pRELUDE_CORE, pRELUDE_RATIO,
	pRELUDE_LIST, pRELUDE_TEXT,
	pRELUDE_PRIMIO, pRELUDE_IO, pRELUDE_PS,
	gLASGOW_ST, gLASGOW_MISC,
	pRELUDE_FB
  ) where

CHK_Ubiq() -- debugging consistency check
\end{code}


\begin{code}
gLASGOW_MISC	= SLIT("PreludeGlaMisc")
gLASGOW_ST	= SLIT("PreludeGlaST")
pRELUDE		= SLIT("Prelude")
pRELUDE_BUILTIN = SLIT("PreludeBuiltin")
pRELUDE_CORE	= SLIT("PreludeCore")
pRELUDE_FB	= SLIT("PreludeFoldrBuild")
pRELUDE_IO	= SLIT("PreludeIO")
pRELUDE_LIST	= SLIT("PreludeList")
pRELUDE_PRIMIO	= SLIT("PreludePrimIO")
pRELUDE_PS	= SLIT("PreludePS")
pRELUDE_RATIO	= SLIT("PreludeRatio")
pRELUDE_TEXT	= SLIT("PreludeText")
\end{code}
