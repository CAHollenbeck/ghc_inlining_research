%
% (c) The AQUA Project, Glasgow University, 1994-1995
%
\section[I386Desc]{The I386 Machine Description}

\begin{code}
#include "HsVersions.h"

module I386Desc (
    	mkI386

    	-- and assorted nonsense referenced by the class methods
    ) where

import AbsCSyn
import PrelInfo	    ( PrimOp(..)
		      IF_ATTACK_PRAGMAS(COMMA tagOf_PrimOp)
			  IF_ATTACK_PRAGMAS(COMMA pprPrimOp)
		    )
import AsmRegAlloc  ( Reg, MachineCode(..), MachineRegisters(..),
		      RegLiveness(..), RegUsage(..), FutureLive(..)
		    )
import CLabel   ( CLabel )
import CmdLineOpts  ( GlobalSwitch(..), stringSwitchSet, switchIsOn, SwitchResult(..) )
import HeapOffs	    ( hpRelToInt )
import MachDesc
import Maybes	    ( Maybe(..) )
import OrdList
import Outputable
import SMRep	    ( SMRep(..), SMSpecRepKind(..), SMUpdateKind(..) )
import I386Code
import I386Gen	    ( i386CodeGen )
import Stix
import StixMacro
import StixPrim
import UniqSupply
import Util
\end{code}

Header sizes depend only on command-line options, not on the target
architecture.  (I think.)

\begin{code}

fhs :: (GlobalSwitch -> SwitchResult) -> Int

fhs switches = 1 + profFHS + ageFHS
  where
    profFHS = if switchIsOn switches SccProfilingOn then 1 else 0
    ageFHS  = if switchIsOn switches SccProfilingOn then 1 else 0

vhs :: (GlobalSwitch -> SwitchResult) -> SMRep -> Int

vhs switches sm = case sm of
    StaticRep _ _	   -> 0
    SpecialisedRep _ _ _ _ -> 0
    GenericRep _ _ _	   -> 0
    BigTupleRep _	   -> 1
    MuTupleRep _	   -> 2 {- (1 + GC_MUT_RESERVED_WORDS) -}
    DataRep _		   -> 1
    DynamicRep		   -> 2
    BlackHoleRep	   -> 0
    PhantomRep		   -> panic "vhs:phantom"

\end{code}

Here we map STG registers onto appropriate Stix Trees.  First, we
handle the two constants, @STK_STUB_closure@ and @vtbl_StdUpdFrame@.
The rest are either in real machine registers or stored as offsets
from BaseReg.

\begin{code}

i386Reg :: (GlobalSwitch -> SwitchResult) -> MagicId -> RegLoc

i386Reg switches x =
    case stgRegMap x of
	Just reg -> Save nonReg
	Nothing -> Always nonReg
    where nonReg = case x of
    	    StkStubReg -> sStLitLbl SLIT("STK_STUB_closure")
    	    StdUpdRetVecReg -> sStLitLbl SLIT("vtbl_StdUpdFrame")
    	    BaseReg -> sStLitLbl SLIT("MainRegTable")
    	    --Hp -> StInd PtrRep (sStLitLbl SLIT("StorageMgrInfo"))
    	    --HpLim -> StInd PtrRep (sStLitLbl SLIT("StorageMgrInfo+4"))
    	    TagReg -> StInd IntRep (StPrim IntSubOp [infoptr, StInt (1*4)])
    	    	      where
    	    	    	  r2 = VanillaReg PtrRep ILIT(2)
    	    	    	  infoptr = case i386Reg switches r2 of
    	    	    	    	    	Always tree -> tree
    	    	    	    	    	Save _ -> StReg (StixMagicId r2)
    	    _ -> StInd (kindFromMagicId x)
	    	       (StPrim IntAddOp [baseLoc, StInt (toInteger (offset*4))])
    	  baseLoc = case stgRegMap BaseReg of
    	    Just _ -> StReg (StixMagicId BaseReg)
    	    Nothing -> sStLitLbl SLIT("MainRegTable")
	  offset = baseRegOffset x

\end{code}

Sizes in bytes.

\begin{code}

size pk = case kindToSize pk of
    {B -> 1; S -> 2; L -> 4; F -> 4; D -> 8 }

\end{code}

Now the volatile saves and restores.  We add the basic guys to the list of ``user''
registers provided.  Note that there are more basic registers on the restore list,
because some are reloaded from constants.

\begin{code}

vsaves switches vols =
    map save ((filter callerSaves) ([BaseReg,SpA,SuA,SpB,SuB,Hp,HpLim,RetReg{-,ActivityReg-}] ++ vols))
    where
	save x = StAssign (kindFromMagicId x) loc reg
    	    	    where reg = StReg (StixMagicId x)
    	    	    	  loc = case i386Reg switches x of
    	    	    	    	    Save loc -> loc
    	    	    	    	    Always loc -> panic "vsaves"

vrests switches vols =
    map restore ((filter callerSaves)
    	([BaseReg,SpA,SuA,SpB,SuB,Hp,HpLim,RetReg{-,ActivityReg-},StkStubReg,StdUpdRetVecReg] ++ vols))
    where
	restore x = StAssign (kindFromMagicId x) reg loc
    	    	    where reg = StReg (StixMagicId x)
    	    	    	  loc = case i386Reg switches x of
    	    	    	    	    Save loc -> loc
    	    	    	    	    Always loc -> panic "vrests"

\end{code}

Static closure sizes.

\begin{code}

charLikeSize, intLikeSize :: Target -> Int

charLikeSize target =
    size PtrRep * (fixedHeaderSize target + varHeaderSize target charLikeRep + 1)
    where charLikeRep = SpecialisedRep CharLikeRep 0 1 SMNormalForm

intLikeSize target =
    size PtrRep * (fixedHeaderSize target + varHeaderSize target intLikeRep + 1)
    where intLikeRep = SpecialisedRep IntLikeRep 0 1 SMNormalForm

mhs, dhs :: (GlobalSwitch -> SwitchResult) -> StixTree

mhs switches = StInt (toInteger words)
  where
    words = fhs switches + vhs switches (MuTupleRep 0)

dhs switches = StInt (toInteger words)
  where
    words = fhs switches + vhs switches (DataRep 0)

\end{code}

Setting up a i386 target.

\begin{code}
mkI386 :: Bool
	-> (GlobalSwitch -> SwitchResult)
	-> (Target,
	    (PprStyle -> [[StixTree]] -> UniqSM Unpretty), -- codeGen
	    Bool,					    -- underscore
	    (String -> String))				    -- fmtAsmLbl

mkI386 decentOS switches =
    let fhs' = fhs switches
    	vhs' = vhs switches
    	i386Reg' = i386Reg switches
    	vsaves' = vsaves switches
    	vrests' = vrests switches
    	hprel = hpRelToInt target
	as = amodeCode target
	as' = amodeCode' target
    	csz = charLikeSize target
    	isz = intLikeSize target
    	mhs' = mhs switches
    	dhs' = dhs switches
    	ps = genPrimCode target
    	mc = genMacroCode target
    	hc = doHeapCheck
    	target = mkTarget {-switches-} fhs' vhs' i386Reg' {-id-} size
    	    	    	  hprel as as'
			  (vsaves', vrests', csz, isz, mhs', dhs', ps, mc, hc)
    	    	    	  {-i386CodeGen decentOS id-}
    in
    (target, i386CodeGen, decentOS, id)
\end{code}



